// script.go — goja JavaScript runtime for YueLink Module Runtime Phase 2C.
//
// Supports http-response scripts only. Scripts receive $request/$response globals
// and call done({body, headers}) to signal a modified response.
//
// Pipeline position: URL Rewrite → Request Header Rewrite → Upstream →
//                    Response Script → Response Header Rewrite → Client
package mitm

import (
	"fmt"
	"io"
	"mime"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/dop251/goja"
)

// ResponseScriptCtx carries the HTTP context passed to the script's globals.
type ResponseScriptCtx struct {
	Method          string
	URL             string
	RequestHeaders  map[string]string
	ResponseStatus  int
	ResponseHeaders map[string]string
	ResponseBody    string
}

// ScriptResult holds the outcome of RunResponseScript.
// Modified is false when the script ran without calling done({...}), or on error.
type ScriptResult struct {
	Modified bool
	Body     string
	Headers  map[string]string
	Error    string
}

const (
	scriptTimeout      = 10 * time.Second
	scriptMaxBodyBytes = 1 << 20 // 1 MB
)

// isTextContent reports whether contentType indicates a textual payload that
// can be decoded to a Go string and passed to a script.
func isTextContent(contentType string) bool {
	if contentType == "" {
		return false
	}
	mt, _, _ := mime.ParseMediaType(contentType)
	if strings.HasPrefix(mt, "text/") {
		return true
	}
	switch mt {
	case "application/json",
		"application/x-www-form-urlencoded",
		"application/javascript",
		"application/xml",
		"application/xhtml+xml":
		return true
	}
	return false
}

// readLimitedBody reads up to scriptMaxBodyBytes from body.
// Returns (content, truncated, error). The caller should not use body after this call.
func readLimitedBody(body io.Reader) (string, bool, error) {
	lr := io.LimitReader(body, scriptMaxBodyBytes+1)
	data, err := io.ReadAll(lr)
	if err != nil {
		return "", false, err
	}
	if int64(len(data)) > scriptMaxBodyBytes {
		return string(data[:scriptMaxBodyBytes]), true, nil
	}
	return string(data), false, nil
}

// RunResponseScript executes a Surge-style http-response script against ctx.
//
// The script receives:
//   - $request  — {method, url, headers}
//   - $response — {status, body, headers}
//   - console.log(...)
//   - $notification.post(title, subtitle, body)  [stub]
//   - $persistentStore.read(key)                 [stub, always ""]
//   - $persistentStore.write(key, value)         [stub, no-op]
//   - done({body, headers})                      — signals result and stops execution
//
// If done() is never called within scriptTimeout, ScriptResult.Modified = false.
func RunResponseScript(code string, ctx ResponseScriptCtx) (result ScriptResult) {
	defer func() {
		if r := recover(); r != nil {
			result.Error = fmt.Sprintf("script panic: %v", r)
			logScript("panic: %v", r)
		}
	}()

	vm := goja.New()

	// ── $request ─────────────────────────────────────────────────────────────
	reqObj := vm.NewObject()
	_ = reqObj.Set("method", ctx.Method)
	_ = reqObj.Set("url", ctx.URL)
	reqHeaders := vm.NewObject()
	for k, v := range ctx.RequestHeaders {
		_ = reqHeaders.Set(k, v)
	}
	_ = reqObj.Set("headers", reqHeaders)
	_ = vm.Set("$request", reqObj)

	// ── $response ────────────────────────────────────────────────────────────
	respObj := vm.NewObject()
	_ = respObj.Set("status", ctx.ResponseStatus)
	_ = respObj.Set("body", ctx.ResponseBody)
	respHeaders := vm.NewObject()
	for k, v := range ctx.ResponseHeaders {
		_ = respHeaders.Set(k, v)
	}
	_ = respObj.Set("headers", respHeaders)
	_ = vm.Set("$response", respObj)

	// ── console.log ──────────────────────────────────────────────────────────
	console := vm.NewObject()
	_ = console.Set("log", func(call goja.FunctionCall) goja.Value {
		parts := make([]string, 0, len(call.Arguments))
		for _, a := range call.Arguments {
			parts = append(parts, fmt.Sprintf("%v", a.Export()))
		}
		logScript("%s", strings.Join(parts, " "))
		return goja.Undefined()
	})
	_ = vm.Set("console", console)

	// ── $notification.post (stub) ─────────────────────────────────────────────
	notification := vm.NewObject()
	_ = notification.Set("post", func(_ goja.FunctionCall) goja.Value {
		return goja.Undefined()
	})
	_ = vm.Set("$notification", notification)

	// ── $persistentStore (stub) ───────────────────────────────────────────────
	store := vm.NewObject()
	_ = store.Set("read", func(_ goja.FunctionCall) goja.Value { return vm.ToValue("") })
	_ = store.Set("write", func(_ goja.FunctionCall) goja.Value { return goja.Undefined() })
	_ = vm.Set("$persistentStore", store)

	// ── done({body, headers}) ─────────────────────────────────────────────────
	// Captured here so the closure can write the result before interrupting the VM.
	var capturedResult ScriptResult
	_ = vm.Set("done", func(call goja.FunctionCall) goja.Value {
		if len(call.Arguments) > 0 {
			if obj, ok := call.Arguments[0].Export().(map[string]interface{}); ok {
				capturedResult.Modified = true
				if b, ok := obj["body"]; ok {
					capturedResult.Body = fmt.Sprintf("%v", b)
				}
				if h, ok := obj["headers"]; ok {
					if hmap, ok := h.(map[string]interface{}); ok {
						capturedResult.Headers = make(map[string]string, len(hmap))
						for k, v := range hmap {
							capturedResult.Headers[k] = fmt.Sprintf("%v", v)
						}
					}
				}
			}
		}
		vm.Interrupt("__done__")
		return goja.Undefined()
	})

	// ── Run with timeout ──────────────────────────────────────────────────────
	timer := time.AfterFunc(scriptTimeout, func() {
		vm.Interrupt("timeout")
	})
	defer timer.Stop()

	_, runErr := vm.RunString(code)
	if runErr == nil {
		// Script completed without calling done() — no modification.
		logScript("script completed without done() — no modification")
		return result
	}

	iErr, ok := runErr.(*goja.InterruptedError)
	if !ok {
		result.Error = fmt.Sprintf("script error: %v", runErr)
		logScript("error: %v", runErr)
		return result
	}

	if iErr.Value() == "__done__" {
		logScript("done() called — modified=%v body_len=%d headers=%d",
			capturedResult.Modified, len(capturedResult.Body), len(capturedResult.Headers))
		return capturedResult
	}

	// Timeout or other interrupt.
	result.Error = fmt.Sprintf("script interrupted: %v", iErr.Value())
	logScript("interrupted: %v", iErr.Value())
	return result
}

// ── Pipeline helpers ───────────────────────────────────────────────────────────

// compiledScript pairs a compiled URL pattern with its JavaScript source.
type compiledScript struct {
	pattern *regexp.Regexp
	code    string
}

// compileScripts builds a []compiledScript from MITMConfig.Scripts.
// Entries with empty code or invalid patterns are skipped.
func compileScripts(scripts []MITMScript) []compiledScript {
	result := make([]compiledScript, 0, len(scripts))
	for _, s := range scripts {
		if s.Code == "" {
			continue
		}
		re, err := regexp.Compile(s.Pattern)
		if err != nil {
			logScript("skipping script — invalid pattern %q: %v", s.Pattern, err)
			continue
		}
		result = append(result, compiledScript{pattern: re, code: s.Code})
	}
	return result
}

// RunResponseScriptsOnHTTP runs matching response scripts against resp.
// Body is read, passed to each matching script, and reconstructed.
// Returns the (possibly modified) *http.Response.
// resp.Body is always replaced with a fresh ReadCloser; callers must close it.
func RunResponseScriptsOnHTTP(scripts []compiledScript, req *http.Request, resp *http.Response, fullURL string) *http.Response {
	if len(scripts) == 0 || resp == nil {
		return resp
	}

	ct := resp.Header.Get("Content-Type")
	if !isTextContent(ct) {
		logScript("skip %s — non-text content-type %q", fullURL, ct)
		return resp
	}

	bodyStr, truncated, err := readLimitedBody(resp.Body)
	if err != nil {
		logScript("body read error for %s: %v", fullURL, err)
		return resp
	}
	if truncated {
		logScript("body truncated at 1MB for %s", fullURL)
	}

	// Build header maps for the script context.
	reqHeaders := make(map[string]string, len(req.Header))
	for k := range req.Header {
		reqHeaders[k] = req.Header.Get(k)
	}
	respHeaders := make(map[string]string, len(resp.Header))
	for k := range resp.Header {
		respHeaders[k] = resp.Header.Get(k)
	}

	ctx := ResponseScriptCtx{
		Method:          req.Method,
		URL:             fullURL,
		RequestHeaders:  reqHeaders,
		ResponseStatus:  resp.StatusCode,
		ResponseHeaders: respHeaders,
		ResponseBody:    bodyStr,
	}

	modified := false
	for _, s := range scripts {
		if !s.pattern.MatchString(fullURL) {
			continue
		}
		logScript("running script for %s", fullURL)
		res := RunResponseScript(s.code, ctx)
		if res.Error != "" {
			logScript("script error for %s: %v", fullURL, res.Error)
			continue
		}
		if res.Modified {
			modified = true
			ctx.ResponseBody = res.Body
			for k, v := range res.Headers {
				ctx.ResponseHeaders[k] = v
			}
		}
	}

	if !modified {
		// Restore body unchanged.
		resp.Body = io.NopCloser(strings.NewReader(bodyStr))
		return resp
	}

	// Apply modifications.
	for k, v := range ctx.ResponseHeaders {
		resp.Header.Set(k, v)
	}
	newBody := ctx.ResponseBody
	resp.Body = io.NopCloser(strings.NewReader(newBody))
	resp.ContentLength = int64(len(newBody))
	resp.Header.Set("Content-Length", fmt.Sprintf("%d", len(newBody)))
	resp.TransferEncoding = nil
	resp.Header.Del("Transfer-Encoding")

	logScript("response modified for %s — new body_len=%d", fullURL, len(newBody))
	return resp
}
