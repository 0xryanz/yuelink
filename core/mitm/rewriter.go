package mitm

import (
	"net/http"
	"regexp"
	"strings"
)

// compiledURLRule holds a compiled regex for URL rewrite matching.
type compiledURLRule struct {
	pattern     *regexp.Regexp
	replacement string
	action      string // "reject", "302", "307"
}

// compiledHeaderRule holds a compiled regex for header rewrite matching.
type compiledHeaderRule struct {
	pattern  string // stored as-is for logging
	re       *regexp.Regexp
	name     string
	value    string
	action   string // "add", "replace", "del"
	response bool   // true = applies to response headers; false = request headers
}

// Rewriter applies URL and Header rewrite rules to intercepted HTTP requests.
// Rules are compiled once at construction time; zero value is a no-op.
type Rewriter struct {
	urlRules    []compiledURLRule
	headerRules []compiledHeaderRule
}

// NewRewriter compiles a set of URL and Header rewrite rules from a MITMConfig.
// Rules that fail to compile are skipped with a log warning.
func NewRewriter(cfg MITMConfig) *Rewriter {
	r := &Rewriter{}
	for _, rule := range cfg.URLRewrites {
		action := strings.ToLower(rule.Action)
		switch action {
		case "reject", "302", "307":
		default:
			logEngine("URL Rewrite: unknown action %q (pattern %q), skipping", rule.Action, rule.Pattern)
			continue
		}
		re, err := regexp.Compile(rule.Pattern)
		if err != nil {
			logEngine("URL Rewrite: bad pattern %q: %v", rule.Pattern, err)
			continue
		}
		r.urlRules = append(r.urlRules, compiledURLRule{
			pattern:     re,
			replacement: rule.Replacement,
			action:      action,
		})
	}
	for _, rule := range cfg.HeaderRewrites {
		action := strings.ToLower(rule.Action)
		isResponse := false
		switch action {
		case "add", "replace", "del":
			// request header rewrite (default)
		case "response-add", "response-replace", "response-del":
			isResponse = true
			action = strings.TrimPrefix(action, "response-") // "add"/"replace"/"del"
		default:
			logEngine("Header Rewrite: unknown action %q (pattern %q), skipping", rule.Action, rule.Pattern)
			continue
		}
		re, err := regexp.Compile(rule.Pattern)
		if err != nil {
			logEngine("Header Rewrite: bad pattern %q: %v", rule.Pattern, err)
			continue
		}
		r.headerRules = append(r.headerRules, compiledHeaderRule{
			pattern:  rule.Pattern,
			re:       re,
			name:     rule.Name,
			value:    rule.Value,
			action:   action,
			response: isResponse,
		})
	}
	logEngine("rewriter built: %d URL rules, %d header rules",
		len(r.urlRules), len(r.headerRules))
	return r
}

// URLRewriteResult is the outcome of applying URL rewrite rules.
type URLRewriteResult struct {
	Matched     bool
	Action      string // "reject", "302", "307"
	RedirectURL string // populated for 302/307 actions
}

// ApplyURL checks url against compiled URL rewrite rules.
// Returns the first matching result, or {Matched: false} if none match.
func (r *Rewriter) ApplyURL(url string) URLRewriteResult {
	for i := range r.urlRules {
		rule := &r.urlRules[i]
		if rule.pattern.MatchString(url) {
			redirectURL := ""
			if rule.action == "302" || rule.action == "307" {
				redirectURL = rule.pattern.ReplaceAllString(url, rule.replacement)
			}
			return URLRewriteResult{
				Matched:     true,
				Action:      rule.action,
				RedirectURL: redirectURL,
			}
		}
	}
	return URLRewriteResult{}
}

// ApplyRequestHeaders modifies request headers in-place.
// Only request-side rules (response == false) whose URL pattern matches are applied.
func (r *Rewriter) ApplyRequestHeaders(fullURL string, header http.Header) {
	r.applyHeaders(fullURL, header, false)
}

// ApplyResponseHeaders modifies response headers in-place.
// Only response-side rules (response == true) whose URL pattern matches are applied.
func (r *Rewriter) ApplyResponseHeaders(fullURL string, header http.Header) {
	r.applyHeaders(fullURL, header, true)
}

// ApplyHeaders is kept for backward compatibility; applies request-side rules.
// Deprecated: use ApplyRequestHeaders.
func (r *Rewriter) ApplyHeaders(fullURL string, header http.Header) {
	r.applyHeaders(fullURL, header, false)
}

func (r *Rewriter) applyHeaders(fullURL string, header http.Header, response bool) {
	for i := range r.headerRules {
		rule := &r.headerRules[i]
		if rule.response != response {
			continue
		}
		if !rule.re.MatchString(fullURL) {
			continue
		}
		name := http.CanonicalHeaderKey(rule.name)
		side := "request"
		if response {
			side = "response"
		}
		switch rule.action {
		case "add":
			logRewrite("%s header add %s: %s (url: %s)", side, name, rule.value, fullURL)
			header.Add(name, rule.value)
		case "replace":
			logRewrite("%s header replace %s: %s (url: %s)", side, name, rule.value, fullURL)
			header.Set(name, rule.value)
		case "del":
			logRewrite("%s header del %s (url: %s)", side, name, fullURL)
			header.Del(name)
		}
	}
}
