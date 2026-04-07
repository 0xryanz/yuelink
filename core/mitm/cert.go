package mitm

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"sync"
	"time"
)

const (
	caCertFilename = "ca.crt"
	caKeyFilename  = "ca.key"
	caValidYears   = 10
)

// mitmDir returns the mitm data subdirectory under homeDir.
func mitmDir(homeDir string) string {
	return filepath.Join(homeDir, "mitm")
}

// caCertPath returns the full path to the CA certificate PEM file.
func caCertPath(homeDir string) string {
	return filepath.Join(mitmDir(homeDir), caCertFilename)
}

// caKeyPath returns the full path to the CA private key PEM file.
func caKeyPath(homeDir string) string {
	return filepath.Join(mitmDir(homeDir), caKeyFilename)
}

// GenerateRootCA creates or loads the Root CA cert.
// homeDir: the YueLink data directory (same as core homeDir).
// Returns CertStatus or error.
func GenerateRootCA(homeDir string) (*CertStatus, error) {
	dir := mitmDir(homeDir)
	certPath := caCertPath(homeDir)
	keyPath := caKeyPath(homeDir)

	// Attempt to reuse existing files if they are valid.
	if status := loadExistingCA(certPath, keyPath); status != nil {
		logCA("reusing existing Root CA (expires %s)", status.ExpiresAt.Format("2006-01-02"))
		return status, nil
	}

	// Ensure directory exists.
	if err := os.MkdirAll(dir, 0700); err != nil {
		return nil, fmt.Errorf("[MITM] failed to create mitm dir: %w", err)
	}

	logCA("generating new ECDSA P-256 Root CA …")

	// Generate ECDSA P-256 key pair.
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("[MITM] key generation failed: %w", err)
	}

	now := time.Now().UTC()
	expiry := now.Add(caValidYears * 365 * 24 * time.Hour)

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("[MITM] serial generation failed: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			Organization: []string{"YueLink"},
			CommonName:   "YueLink Module Runtime CA",
		},
		NotBefore:             now,
		NotAfter:              expiry,
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            1,
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, template, &privKey.PublicKey, privKey)
	if err != nil {
		return nil, fmt.Errorf("[MITM] cert creation failed: %w", err)
	}

	// Write certificate PEM.
	certFile, err := os.OpenFile(certPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0644)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to open cert file: %w", err)
	}
	defer certFile.Close()
	if err := pem.Encode(certFile, &pem.Block{Type: "CERTIFICATE", Bytes: certDER}); err != nil {
		return nil, fmt.Errorf("[MITM] failed to write cert PEM: %w", err)
	}

	// Write private key PEM.
	keyDER, err := x509.MarshalECPrivateKey(privKey)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to marshal private key: %w", err)
	}
	keyFile, err := os.OpenFile(keyPath, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return nil, fmt.Errorf("[MITM] failed to open key file: %w", err)
	}
	defer keyFile.Close()
	if err := pem.Encode(keyFile, &pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER}); err != nil {
		return nil, fmt.Errorf("[MITM] failed to write key PEM: %w", err)
	}

	fingerprint := sha256Fingerprint(certDER)
	logCA("Root CA generated, fingerprint: %s", fingerprint)

	return &CertStatus{
		Exists:      true,
		Fingerprint: fingerprint,
		CreatedAt:   now,
		ExpiresAt:   expiry,
		PEMPath:     certPath,
	}, nil
}

// GetRootCAStatus returns current CA status without generating.
// Returns nil if CA doesn't exist or is invalid.
func GetRootCAStatus(homeDir string) *CertStatus {
	return loadExistingCA(caCertPath(homeDir), caKeyPath(homeDir))
}

// ExportRootCAPEM returns the CA certificate PEM bytes for installation.
func ExportRootCAPEM(homeDir string) ([]byte, error) {
	certPath := caCertPath(homeDir)
	data, err := os.ReadFile(certPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, errors.New("[MITM] CA certificate does not exist; call GenerateRootCA first")
		}
		return nil, fmt.Errorf("[MITM] failed to read CA cert: %w", err)
	}
	return data, nil
}

// loadExistingCA tries to parse the cert + key at the given paths.
// Returns nil if either file is missing, unreadable, or the cert is expired.
func loadExistingCA(certPath, keyPath string) *CertStatus {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil
	}
	if _, err := os.Stat(keyPath); err != nil {
		return nil // key file must also exist
	}

	block, _ := pem.Decode(certPEM)
	if block == nil || block.Type != "CERTIFICATE" {
		return nil
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil
	}
	if time.Now().After(cert.NotAfter) {
		logCA("existing CA expired on %s, will regenerate", cert.NotAfter.Format("2006-01-02"))
		return nil
	}

	return &CertStatus{
		Exists:      true,
		Fingerprint: sha256Fingerprint(block.Bytes),
		CreatedAt:   cert.NotBefore,
		ExpiresAt:   cert.NotAfter,
		PEMPath:     certPath,
	}
}

// sha256Fingerprint computes the colon-separated hex SHA-256 of raw DER bytes.
func sha256Fingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return hex.EncodeToString(sum[:])
}

// ---------------------------------------------------------------------------
// LeafCertCache – per-hostname TLS certs signed by the Root CA
// ---------------------------------------------------------------------------

const leafCertCacheMax = 200 // max cached leaf certs; oldest evicted when full

// LeafCertCache generates and caches per-hostname TLS leaf certificates
// signed by the Root CA. Leaf certs are valid for 24 h; expired certs are
// evicted on next access. Cache is capped at leafCertCacheMax entries.
type LeafCertCache struct {
	mu     sync.Mutex
	caCert *x509.Certificate
	caKey  *ecdsa.PrivateKey
	cache  map[string]*tls.Certificate
}

// NewLeafCertCache loads the Root CA from disk and returns a ready cache.
// Returns an error if the CA files are missing or unreadable.
func NewLeafCertCache(homeDir string) (*LeafCertCache, error) {
	certPEM, err := os.ReadFile(caCertPath(homeDir))
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf cache: cannot read CA cert: %w", err)
	}
	keyPEM, err := os.ReadFile(caKeyPath(homeDir))
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf cache: cannot read CA key: %w", err)
	}

	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil {
		return nil, fmt.Errorf("[MITM] leaf cache: invalid CA cert PEM")
	}
	caCert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf cache: parse CA cert: %w", err)
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		return nil, fmt.Errorf("[MITM] leaf cache: invalid CA key PEM")
	}
	caKey, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf cache: parse CA key: %w", err)
	}

	return &LeafCertCache{
		caCert: caCert,
		caKey:  caKey,
		cache:  make(map[string]*tls.Certificate),
	}, nil
}

// GetOrCreate returns a TLS certificate for hostname, generating one if not
// cached or if the cached entry has expired (< 1 min remaining).
func (lc *LeafCertCache) GetOrCreate(hostname string) (*tls.Certificate, error) {
	// Strip port if present.
	host := hostname
	if h, _, err := net.SplitHostPort(hostname); err == nil {
		host = h
	}

	lc.mu.Lock()
	defer lc.mu.Unlock()

	if cert, ok := lc.cache[host]; ok {
		if cert.Leaf != nil && time.Until(cert.Leaf.NotAfter) > time.Minute {
			return cert, nil
		}
		delete(lc.cache, host)
	}

	cert, err := lc.generateLeaf(host)
	if err != nil {
		return nil, err
	}

	// Evict one entry if the cache is at capacity (simple strategy: remove
	// the first expired entry found, or any entry if none are expired).
	if len(lc.cache) >= leafCertCacheMax {
		var evictKey string
		for k, c := range lc.cache {
			if c.Leaf == nil || time.Until(c.Leaf.NotAfter) <= 0 {
				evictKey = k
				break
			}
			if evictKey == "" {
				evictKey = k // fallback: evict any entry
			}
		}
		if evictKey != "" {
			delete(lc.cache, evictKey)
			logCA("cache full (%d), evicted %s", leafCertCacheMax, evictKey)
		}
	}

	lc.cache[host] = cert
	logCA("issued leaf cert for %s", host)
	return cert, nil
}

// generateLeaf creates a new 24-hour leaf certificate for hostname,
// signed by the Root CA held in lc.
func (lc *LeafCertCache) generateLeaf(hostname string) (*tls.Certificate, error) {
	privKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf gen key: %w", err)
	}

	now := time.Now().UTC()
	expiry := now.Add(24 * time.Hour)

	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf gen serial: %w", err)
	}

	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: hostname},
		NotBefore:    now,
		NotAfter:     expiry,
		KeyUsage:     x509.KeyUsageDigitalSignature,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}
	// Use IP SAN for IP addresses, DNS SAN for hostnames.
	if ip := net.ParseIP(hostname); ip != nil {
		template.IPAddresses = []net.IP{ip}
	} else {
		template.DNSNames = []string{hostname}
	}

	certDER, err := x509.CreateCertificate(rand.Reader, template, lc.caCert, &privKey.PublicKey, lc.caKey)
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf sign: %w", err)
	}

	leafX509, err := x509.ParseCertificate(certDER)
	if err != nil {
		return nil, fmt.Errorf("[MITM] leaf parse: %w", err)
	}

	return &tls.Certificate{
		Certificate: [][]byte{certDER},
		PrivateKey:  privKey,
		Leaf:        leafX509,
	}, nil
}
