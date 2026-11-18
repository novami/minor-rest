// Package run převádí výsledek httpclient na DTO pro frontend (kap. 11.2).
package run

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
	"strings"

	"github.com/novami/minor-rest/internal/httpclient"
	"github.com/novami/minor-rest/internal/model"
)

// Kódy chyb.
const (
	ErrNotFound = "RUN_NOT_FOUND" // výsledek už není v paměti (držíme posledních 20)
	ErrInternal = "INTERNAL_ERROR"
)

// MaxView je maximum textu těla poslaného do UI (zbytek jen přes uložení do souboru).
const MaxView = 2 << 20

type Input struct {
	RunID     string        `json:"runID" yaml:"runID"`
	ProjectID string        `json:"projectID" yaml:"projectID"`
	Rel       string        `json:"rel" yaml:"rel"`
	Request   model.Request `json:"request" yaml:"request"`
}

type Error struct {
	Code   string `json:"code" yaml:"code"`
	Detail string `json:"detail,omitempty" yaml:"detail,omitempty"`
}

type Result struct {
	RunID         string                `json:"runID" yaml:"runID"`
	Error         *Error                `json:"error,omitempty" yaml:"error,omitempty"`
	Status        int                   `json:"status" yaml:"status"`
	StatusText    string                `json:"statusText" yaml:"statusText"`
	Proto         string                `json:"proto" yaml:"proto"`
	RemoteAddr    string                `json:"remoteAddr" yaml:"remoteAddr"`
	LocalAddr     string                `json:"localAddr" yaml:"localAddr"`
	ResolvedAddrs []string              `json:"resolvedAddrs" yaml:"resolvedAddrs"`
	TLS           *httpclient.TLSInfo   `json:"tls,omitempty" yaml:"tls,omitempty"`
	Headers       []model.KV            `json:"headers" yaml:"headers"`
	Sizes         httpclient.Sizes      `json:"sizes" yaml:"sizes"`
	Timing        httpclient.Timing     `json:"timing" yaml:"timing"`
	Redirects     []httpclient.Redirect `json:"redirects" yaml:"redirects"`
	Sent          httpclient.Sent       `json:"sent" yaml:"sent"`
	ContentType   string                `json:"contentType" yaml:"contentType"`
	Charset       string                `json:"charset" yaml:"charset"`
	IsBinary      bool                  `json:"isBinary" yaml:"isBinary"`
	Truncated     bool                  `json:"truncated" yaml:"truncated"`
	Unresolved    []string              `json:"unresolved" yaml:"unresolved"`
}

type BodyView struct {
	Text    string `json:"text" yaml:"text"`
	Lang    string `json:"lang" yaml:"lang"` // json | xml | html | text
	Size    int64  `json:"size" yaml:"size"`
	Partial bool   `json:"partial" yaml:"partial"`
	DataURL string `json:"dataURL,omitempty" yaml:"dataURL,omitempty"` // obrázky (F5)
}

// ErrorOf převede chybu (`KÓD: detail`) na Error.
func ErrorOf(err error) *Error {
	var he *httpclient.Error
	if errors.As(err, &he) {
		return &Error{Code: he.Code, Detail: he.Detail}
	}
	s := err.Error()
	code, detail, _ := strings.Cut(s, ": ")
	if !isCode(code) {
		return &Error{Code: ErrInternal, Detail: s}
	}
	return &Error{Code: code, Detail: detail}
}

func isCode(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if (c < 'A' || c > 'Z') && (c < '0' || c > '9') && c != '_' {
			return false
		}
	}
	return true
}

// FromResult sestaví DTO; res může být částečný (při chybě) nebo nil.
func FromResult(runID string, res *httpclient.Result, err error, unresolved []string) Result {
	out := Result{RunID: runID, Unresolved: unresolved}
	if res != nil {
		out.Sent, out.Timing, out.Redirects = res.Sent, res.Timing, res.Redirects
		if err == nil {
			out.Status, out.StatusText, out.Proto = res.Status, res.StatusText, res.Proto
			out.RemoteAddr, out.LocalAddr, out.ResolvedAddrs = res.RemoteAddr, res.LocalAddr, res.ResolvedAddrs
			out.TLS, out.Headers, out.Sizes = res.TLS, res.Headers, res.Sizes
			out.ContentType, out.Charset, out.IsBinary, out.Truncated = res.ContentType, res.Charset, res.IsBinary, res.Truncated
		}
	}
	if err != nil {
		out.Error = ErrorOf(err)
	}
	// nil slice by v JSON byl null
	out.ResolvedAddrs = orEmpty(out.ResolvedAddrs)
	out.Headers = orEmpty(out.Headers)
	out.Redirects = orEmpty(out.Redirects)
	out.Unresolved = orEmpty(out.Unresolved)
	out.Sent.Headers = orEmpty(out.Sent.Headers)
	return out
}

func orEmpty[T any](s []T) []T {
	if s == nil {
		return []T{}
	}
	return s
}

// View vrátí tělo pro zobrazení v UTF-8; pretty odsadí JSON (nevalidní nechá beze změny).
func View(res *httpclient.Result, pretty bool) (BodyView, error) {
	v := BodyView{Lang: lang(res.ContentType)}
	if res.Body == nil || res.IsBinary {
		if res.Body != nil {
			v.Size = res.Body.Size()
		}
		return v, nil
	}
	v.Size = res.Body.Size()
	f, err := res.Body.Open()
	if err != nil {
		return v, err
	}
	defer f.Close()
	b, err := io.ReadAll(io.LimitReader(f, MaxView))
	if err != nil {
		return v, err
	}
	v.Partial = v.Size > int64(len(b))
	text := httpclient.ToUTF8(b, res.Charset)
	if pretty && v.Lang == "json" && !v.Partial {
		var buf bytes.Buffer
		if json.Indent(&buf, []byte(text), "", "  ") == nil {
			text = buf.String()
		}
	}
	v.Text = text
	return v, nil
}

func lang(mt string) string {
	switch {
	case strings.Contains(mt, "json"):
		return "json"
	case strings.Contains(mt, "html"):
		return "html"
	case strings.Contains(mt, "xml"):
		return "xml"
	}
	return "text"
}
