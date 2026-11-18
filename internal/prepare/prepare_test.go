package prepare

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/novami/minor-rest/internal/model"
)

func kv(name, value string, on bool) model.KV { return model.KV{Name: name, Value: value, Enabled: on} }
func v(name, value string) model.Var          { return model.Var{Name: name, Value: value, Enabled: true} }
func ptr[T any](x T) *T                       { return &x }

func TestPrepare(t *testing.T) {
	in := Input{
		Project: model.ProjectConfig{
			Vars:     []model.Var{v("host", "api.test"), v("who", "project")},
			Headers:  []model.KV{kv("X-Project", "1", true), kv("x-team", "p", true), kv("Accept", "", false)},
			Settings: model.HTTPSettings{TimeoutMs: ptr(5000), HTTPVersion: ptr("http1")},
		},
		Folders: []Folder{
			{Rel: "api", Config: model.FolderConfig{Vars: []model.Var{v("who", "api")}, Headers: []model.KV{kv("X-Team", "{{who}}", true)}}},
			{Rel: "api/users", Config: model.FolderConfig{Vars: []model.Var{v("who", "users")}}},
		},
		Request: model.Request{
			Method: "post",
			URL:    "{{host}}/users/:id",
			Params: model.Params{
				Path:  []model.PathParam{{Name: "id", Value: "{{id}}"}},
				Query: []model.KV{kv("q", "{{who}}", true), kv("off", "x", false)},
			},
			Headers:  []model.KV{kv("X-Project", "", false), kv("User-Agent", "", false), kv("X-Req", "{{missing}}", true)},
			Vars:     []model.Var{v("id", "42")},
			Body:     model.Body{Type: model.BodyForm, Form: []model.KV{kv("a", "{{id}}", true), kv("b", "x", false)}},
			Settings: model.HTTPSettings{TimeoutMs: ptr(1000)},
		},
		Defaults:  model.HTTPSettings{HTTPVersion: ptr("auto"), FollowRedirects: ptr(true), MaxRedirects: ptr(10), VerifyTLS: ptr(true)},
		UserAgent: "MinorREST/test",
	}
	p, err := Prepare(in)
	if err != nil {
		t.Fatal(err)
	}
	if p.Request.Method != "POST" || p.Request.URL != "http://api.test/users/42?q=users" {
		t.Errorf("method/url = %s %s", p.Request.Method, p.Request.URL)
	}
	wantH := []model.KV{kv("X-Team", "users", true), kv("X-Req", "{{missing}}", true)}
	if !reflect.DeepEqual(p.Request.Headers, wantH) {
		t.Errorf("headers = %+v", p.Request.Headers)
	}
	if !reflect.DeepEqual(p.Request.NoAuto, []string{"User-Agent", "Accept"}) {
		t.Errorf("noAuto = %v", p.Request.NoAuto)
	}
	if !reflect.DeepEqual(p.Request.Body.Form, []model.KV{kv("a", "42", true)}) {
		t.Errorf("form = %+v", p.Request.Body.Form)
	}
	o := p.Options
	if o.Timeout != time.Second || o.HTTPVersion != "http1" || !o.FollowRedirects || o.MaxRedirects != 10 || !o.VerifyTLS || o.UserAgent != "MinorREST/test" {
		t.Errorf("options = %+v", o)
	}
	if !reflect.DeepEqual(p.Unresolved, []string{"missing"}) {
		t.Errorf("unresolved = %v", p.Unresolved)
	}
}

func TestPrepareErrors(t *testing.T) {
	for _, tc := range []struct{ url, code string }{
		{"{{host}}/x", "VAR_UNRESOLVED_HOST"},
		{"http://[::1", "URL_INVALID"},
	} {
		_, err := Prepare(Input{Request: model.Request{Method: "GET", URL: tc.url}})
		if err == nil || !strings.HasPrefix(err.Error(), tc.code) {
			t.Errorf("%s: err = %v, want %s", tc.url, err, tc.code)
		}
	}
}

// Zapnutý řádek na nižší úrovni zruší vypnutí z vyšší (automatická hlavička se pošle).
func TestReenableAuto(t *testing.T) {
	p, err := Prepare(Input{
		Project: model.ProjectConfig{Headers: []model.KV{kv("Accept", "", false)}},
		Request: model.Request{Method: "GET", URL: "x.test", Headers: []model.KV{kv("accept", "text/plain", true)}},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Request.NoAuto) != 0 || len(p.Request.Headers) != 1 {
		t.Errorf("noAuto = %v, headers = %v", p.Request.NoAuto, p.Request.Headers)
	}
}
