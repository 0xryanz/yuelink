package mitm

import (
	"io"
	"net/http"
	"strings"
	"testing"
)

// ── isTextContent ──────────────────────────────────────────────────────────────

func TestIsTextContent(t *testing.T) {
	cases := []struct {
		ct   string
		want bool
	}{
		{"application/json", true},
		{"application/json; charset=utf-8", true},
		{"text/html", true},
		{"text/plain; charset=utf-8", true},
		{"application/javascript", true},
		{"application/xml", true},
		{"application/x-www-form-urlencoded", true},
		{"image/png", false},
		{"image/jpeg", false},
		{"application/octet-stream", false},
		{"video/mp4", false},
		{"", false},
	}
	for _, c := range cases {
		got := isTextContent(c.ct)
		if got != c.want {
			t.Errorf("isTextContent(%q) = %v, want %v", c.ct, got, c.want)
		}
	}
}

// ── readLimitedBody ────────────────────────────────────────────────────────────

func TestReadLimitedBody_Small(t *testing.T) {
	body := strings.NewReader("hello world")
	s, truncated, err := readLimitedBody(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if truncated {
		t.Error("expected not truncated for small body")
	}
	if s != "hello world" {
		t.Errorf("got %q, want %q", s, "hello world")
	}
}

func TestReadLimitedBody_Truncation(t *testing.T) {
	// Build a body slightly larger than the 1MB limit.
	big := make([]byte, scriptMaxBodyBytes+100)
	for i := range big {
		big[i] = 'x'
	}
	body := strings.NewReader(string(big))
	s, truncated, err := readLimitedBody(body)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !truncated {
		t.Error("expected truncated for oversized body")
	}
	if int64(len(s)) != scriptMaxBodyBytes {
		t.Errorf("truncated body length = %d, want %d", len(s), scriptMaxBodyBytes)
	}
}

// ── RunResponseScript ──────────────────────────────────────────────────────────

func TestRunResponseScript_JSONRewrite(t *testing.T) {
	code := `
var data = JSON.parse($response.body);
data.injected = true;
done({ body: JSON.stringify(data), headers: $response.headers });
`
	ctx := ResponseScriptCtx{
		Method:         "GET",
		URL:            "https://api.example.com/data",
		RequestHeaders: map[string]string{"Accept": "application/json"},
		ResponseStatus: 200,
		ResponseHeaders: map[string]string{
			"Content-Type": "application/json",
		},
		ResponseBody: `{"name":"test"}`,
	}

	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("script error: %s", result.Error)
	}
	if !result.Modified {
		t.Fatal("expected Modified = true")
	}
	if !strings.Contains(result.Body, `"injected":true`) {
		t.Errorf("expected injected field in body, got: %s", result.Body)
	}
}

func TestRunResponseScript_HeaderModify(t *testing.T) {
	code := `
var headers = $response.headers;
headers["X-Custom"] = "YueLink";
done({ body: $response.body, headers: headers });
`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://api.example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{"Content-Type": "text/plain"},
		ResponseBody:    "hello",
	}

	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("script error: %s", result.Error)
	}
	if !result.Modified {
		t.Fatal("expected Modified = true")
	}
	if result.Headers["X-Custom"] != "YueLink" {
		t.Errorf("expected X-Custom=YueLink, got headers=%v", result.Headers)
	}
}

func TestRunResponseScript_NoDone(t *testing.T) {
	// Script that doesn't call done() → Modified = false.
	code := `
console.log("no modification");
`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{},
		ResponseBody:    "original",
	}
	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("unexpected error: %s", result.Error)
	}
	if result.Modified {
		t.Error("expected Modified = false when done() not called")
	}
}

func TestRunResponseScript_DoneNoArgs(t *testing.T) {
	// done() with no arguments → Modified = false.
	code := `done();`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{},
		ResponseBody:    "original",
	}
	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("unexpected error: %s", result.Error)
	}
	if result.Modified {
		t.Error("expected Modified = false for done() with no args")
	}
}

func TestRunResponseScript_SyntaxError(t *testing.T) {
	code := `this is not valid javascript !!!`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{},
		ResponseBody:    "body",
	}
	result := RunResponseScript(code, ctx)
	if result.Error == "" {
		t.Error("expected a script error for invalid JS")
	}
	if result.Modified {
		t.Error("expected Modified = false on script error")
	}
}

func TestRunResponseScript_ConsoleLog(t *testing.T) {
	// console.log should not crash and should not affect result.
	code := `
console.log("test", 42, true);
done({ body: "logged", headers: {} });
`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{},
		ResponseBody:    "original",
	}
	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("script error: %s", result.Error)
	}
	if !result.Modified {
		t.Fatal("expected Modified = true")
	}
	if result.Body != "logged" {
		t.Errorf("expected body='logged', got %q", result.Body)
	}
}

func TestRunResponseScript_StubAPIs(t *testing.T) {
	// $persistentStore and $notification must not crash.
	code := `
$persistentStore.write("k", "v");
var v = $persistentStore.read("k");
$notification.post("title", "sub", "body");
done({ body: "ok-" + v, headers: {} });
`
	ctx := ResponseScriptCtx{
		Method:          "GET",
		URL:             "https://example.com/",
		RequestHeaders:  map[string]string{},
		ResponseStatus:  200,
		ResponseHeaders: map[string]string{},
		ResponseBody:    "body",
	}
	result := RunResponseScript(code, ctx)
	if result.Error != "" {
		t.Fatalf("script error: %s", result.Error)
	}
	// read() always returns "" (stub) so body = "ok-"
	if result.Body != "ok-" {
		t.Errorf("expected body='ok-', got %q", result.Body)
	}
}

// ── RunResponseScriptsOnHTTP ──────────────────────────────────────────────────

func makeTestResp(body, ct string, status int) *http.Response {
	return &http.Response{
		StatusCode: status,
		Header: http.Header{
			"Content-Type": []string{ct},
		},
		Body: io.NopCloser(strings.NewReader(body)),
	}
}

func makeTestReq(method, url string) *http.Request {
	req, _ := http.NewRequest(method, url, nil)
	return req
}

func TestRunResponseScriptsOnHTTP_JSONRewrite(t *testing.T) {
	scripts := compileScripts([]MITMScript{
		{
			Pattern: `https://api\.example\.com/`,
			Code: `
var data = JSON.parse($response.body);
data.modified = true;
done({ body: JSON.stringify(data), headers: $response.headers });
`,
		},
	})

	req := makeTestReq("GET", "https://api.example.com/data")
	resp := makeTestResp(`{"x":1}`, "application/json", 200)

	out := RunResponseScriptsOnHTTP(scripts, req, resp, "https://api.example.com/data")
	defer out.Body.Close()

	outBody, _ := io.ReadAll(out.Body)
	if !strings.Contains(string(outBody), `"modified":true`) {
		t.Errorf("expected modified=true in body, got: %s", outBody)
	}
}

func TestRunResponseScriptsOnHTTP_NonText_Skipped(t *testing.T) {
	scripts := compileScripts([]MITMScript{
		{
			Pattern: `.*`,
			Code:    `done({ body: "should not run", headers: {} });`,
		},
	})

	req := makeTestReq("GET", "https://example.com/image.png")
	resp := makeTestResp("PNG binary data", "image/png", 200)

	out := RunResponseScriptsOnHTTP(scripts, req, resp, "https://example.com/image.png")
	defer out.Body.Close()

	outBody, _ := io.ReadAll(out.Body)
	// Non-text body should be returned unchanged.
	if string(outBody) != "PNG binary data" {
		t.Errorf("expected unchanged body for non-text, got: %s", outBody)
	}
}

func TestRunResponseScriptsOnHTTP_NoMatch(t *testing.T) {
	scripts := compileScripts([]MITMScript{
		{
			Pattern: `https://other\.com/`,
			Code:    `done({ body: "rewritten", headers: {} });`,
		},
	})

	req := makeTestReq("GET", "https://api.example.com/data")
	resp := makeTestResp("original", "text/plain", 200)

	out := RunResponseScriptsOnHTTP(scripts, req, resp, "https://api.example.com/data")
	defer out.Body.Close()

	outBody, _ := io.ReadAll(out.Body)
	if string(outBody) != "original" {
		t.Errorf("expected unchanged body for non-matching URL, got: %s", outBody)
	}
}

func TestRunResponseScriptsOnHTTP_ContentLengthUpdated(t *testing.T) {
	newBody := `{"replaced":true}`
	scripts := compileScripts([]MITMScript{
		{
			Pattern: `.*`,
			Code:    `done({ body: '{"replaced":true}', headers: $response.headers });`,
		},
	})

	req := makeTestReq("GET", "https://api.example.com/")
	resp := makeTestResp(`{"original":true}`, "application/json", 200)

	out := RunResponseScriptsOnHTTP(scripts, req, resp, "https://api.example.com/")
	defer out.Body.Close()

	if out.ContentLength != int64(len(newBody)) {
		t.Errorf("ContentLength = %d, want %d", out.ContentLength, len(newBody))
	}
}

// ── compileScripts ────────────────────────────────────────────────────────────

func TestCompileScripts_InvalidPattern(t *testing.T) {
	// Invalid regexp should be silently skipped.
	scripts := compileScripts([]MITMScript{
		{Pattern: `[invalid`, Code: `done({});`},
		{Pattern: `.*`, Code: `done({ body: "ok", headers: {} });`},
	})
	if len(scripts) != 1 {
		t.Errorf("expected 1 compiled script (invalid pattern skipped), got %d", len(scripts))
	}
}

func TestCompileScripts_EmptyCode(t *testing.T) {
	scripts := compileScripts([]MITMScript{
		{Pattern: `.*`, Code: ``},
	})
	if len(scripts) != 0 {
		t.Errorf("expected 0 compiled scripts (empty code skipped), got %d", len(scripts))
	}
}

// ── CollectResponseScripts ────────────────────────────────────────────────────

func TestCollectResponseScripts_OnlyHttpResponse(t *testing.T) {
	modules := []ModuleRecord{
		{
			Enabled: true,
			Scripts: []ModuleScript{
				{ScriptType: "http-response", Pattern: ".*", ScriptContent: "done({});"},
				{ScriptType: "http-request", Pattern: ".*", ScriptContent: "done({});"},
				{ScriptType: "cron", Pattern: "", ScriptContent: "log()"},
			},
		},
	}
	result := CollectResponseScripts(modules)
	if len(result) != 1 {
		t.Errorf("expected 1 result, got %d", len(result))
	}
	if result[0].Code != "done({});" {
		t.Errorf("unexpected code: %q", result[0].Code)
	}
}

func TestCollectResponseScripts_DisabledModule(t *testing.T) {
	modules := []ModuleRecord{
		{
			Enabled: false,
			Scripts: []ModuleScript{
				{ScriptType: "http-response", Pattern: ".*", ScriptContent: "done({});"},
			},
		},
	}
	result := CollectResponseScripts(modules)
	if len(result) != 0 {
		t.Errorf("expected 0 results for disabled module, got %d", len(result))
	}
}

func TestCollectResponseScripts_MissingContent(t *testing.T) {
	modules := []ModuleRecord{
		{
			Enabled: true,
			Scripts: []ModuleScript{
				{ScriptType: "http-response", Pattern: ".*", ScriptContent: ""},
			},
		},
	}
	result := CollectResponseScripts(modules)
	if len(result) != 0 {
		t.Errorf("expected 0 results (missing content), got %d", len(result))
	}
}
