package model

import (
	"reflect"
	"strings"
	"testing"

	"golang.org/x/text/unicode/norm"
)

func TestRequestRoundtrip(t *testing.T) {
	timeout := 5000
	in := NewRequest("01JCX7AAAAAAAAAAAAAAAAAAAA", "Seznam uživatelů")
	in.Seq = 3
	in.Method = MethodPost
	in.URL = "{{baseUrl}}/users/:id"
	in.Params = Params{
		Query: []KV{{Name: "q", Value: "kůň", Enabled: true}, {Name: "page", Value: "2"}},
		Path:  []PathParam{{Name: "id", Value: "42"}},
	}
	in.Headers = []KV{{Name: "X-Trace", Value: "{{$uuid}}", Enabled: true}}
	in.Auth = Auth{Type: AuthBearer, Bearer: &BearerAuth{Token: "{{token}}", Prefix: "Bearer"}}
	in.Body = Body{Type: BodyJSON, Raw: "{\n  \"jméno\": \"Žluťoučký\",\n\t\"x\": 1\n}\n"}
	in.Settings.TimeoutMs = &timeout

	data, err := MarshalYAML(in)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "raw: |") {
		t.Errorf("víceřádkové tělo není blok:\n%s", data)
	}
	for _, k := range []string{"vars:", "extract:", "docs:", "followRedirects"} {
		if strings.Contains(string(data), k) {
			t.Errorf("prázdné pole %q se zapsalo:\n%s", k, data)
		}
	}

	var out Request
	if err := UnmarshalYAML(data, &out); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(in, out) {
		t.Errorf("roundtrip nesedí\nin:  %+v\nout: %+v", in, out)
	}
}

func TestUnmarshalDefaultsAndNFC(t *testing.T) {
	nfd := norm.NFD.String("Kůň")
	src := "id: x\nname: " + nfd + "\nmethod: GET\nurl: u\nheaders:\n  - { name: A, value: b }\n  - { name: C, value: d, enabled: false }\n"
	var r Request
	if err := UnmarshalYAML([]byte(src), &r); err != nil {
		t.Fatal(err)
	}
	if r.Name != "Kůň" || r.Name == nfd {
		t.Errorf("name není NFC: %q", r.Name)
	}
	if !r.Headers[0].Enabled || r.Headers[1].Enabled {
		t.Errorf("enabled: %+v", r.Headers)
	}
	if err := UnmarshalYAML([]byte("name: [x"), &r); err == nil || !strings.HasPrefix(err.Error(), ErrYAMLInvalid) {
		t.Errorf("čekán %s, je %v", ErrYAMLInvalid, err)
	}
}

func TestSlugify(t *testing.T) {
	long := strings.Repeat("a", 59) + " b"
	tests := []struct{ in, want string }{
		{"Příliš žluťoučký kůň", "prilis-zlutoucky-kun"},
		{norm.NFD.String("Úpěl ďábelské ódy"), "upel-dabelske-ody"},
		{"  Łódź / Straße -- Ærø ", "lodz-strasse-aero"},
		{"GET /users/{id}", "get-users-id"},
		{"!!!", "polozka"},
		{"", "polozka"},
		{"日本語", "polozka"},
		{long, strings.Repeat("a", 59)},
	}
	for _, tt := range tests {
		if got := Slugify(tt.in); got != tt.want {
			t.Errorf("Slugify(%q) = %q, chci %q", tt.in, got, tt.want)
		}
	}
}

func TestUniqueSlug(t *testing.T) {
	taken := map[string]bool{"uzivatele": true, "uzivatele-2": true}
	has := func(s string) bool { return taken[s] }
	tests := []struct{ in, want string }{
		{"nove", "nove"},
		{"Uzivatele", "Uzivatele-3"}, // case-insensitive kolize
		{"", "polozka"},
	}
	for _, tt := range tests {
		if got := UniqueSlug(tt.in, has); got != tt.want {
			t.Errorf("UniqueSlug(%q) = %q, chci %q", tt.in, got, tt.want)
		}
	}
	long := strings.Repeat("x", 60)
	got := UniqueSlug(long, func(s string) bool { return s == long })
	if got != strings.Repeat("x", 58)+"-2" {
		t.Errorf("dlouhý slug: %q", got)
	}
}

func TestFillNilSlices(t *testing.T) {
	r := NewRequest("x", "y")
	r.Body.Form = []KV{{Name: "a"}}
	FillNilSlices(&r)
	if r.Headers == nil || r.Params.Query == nil || r.Body.Multipart == nil || len(r.Body.Form) != 1 {
		t.Errorf("%+v", r)
	}
}

func TestHTTPSettingsOver(t *testing.T) {
	v1, v2, zero, ten, no := "http1", "auto", 0, 10, false
	got := HTTPSettings{HTTPVersion: &v1, MaxRedirects: &zero}.Over(HTTPSettings{HTTPVersion: &v2, MaxRedirects: &ten, VerifyTLS: &no})
	if *got.HTTPVersion != "http1" || *got.MaxRedirects != 0 || got.VerifyTLS == nil || *got.VerifyTLS || got.TimeoutMs != nil {
		t.Fatalf("Over: %+v", got)
	}
}
