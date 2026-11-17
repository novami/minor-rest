package vars

import (
	"reflect"
	"strings"
	"testing"

	"github.com/novami/minor-rest/internal/model"
)

func v(name, value string) model.Var { return model.Var{Name: name, Value: value, Enabled: true} }

func TestResolvePriorityAndUnknown(t *testing.T) {
	off := v("x", "vypnutá")
	off.Enabled = false
	r := New(
		Scope{Source: SourceRuntime, Vars: []model.Var{v("token", "runtime")}},
		Scope{Source: SourceRequest, Vars: []model.Var{off, v("page", "2")}},
		Scope{Source: SourceFolder, Ref: "a/b", Vars: []model.Var{v("x", "složka-b")}},
		Scope{Source: SourceFolder, Ref: "a", Vars: []model.Var{v("x", "složka-a"), v("host", "a.cz")}},
		Scope{Source: SourceEnvironment, Vars: []model.Var{v("token", "env"), v("host", "env.cz")}},
		Scope{Source: SourceProject, Vars: []model.Var{v("base", "https://{{host}}/api")}},
		Scope{Source: SourceGlobal, Vars: []model.Var{v("base", "global")}},
	)
	tests := []struct{ in, want string; unresolved []string }{
		{"{{token}}", "runtime", nil},
		{"{{ x }}", "složka-b", nil},
		{"{{base}}/u?p={{page}}", "https://a.cz/api/u?p=2", nil},
		{"{{nic}}/{{$neznama}}/{{nic}}", "{{nic}}/{{$neznama}}/{{nic}}", []string{"nic", "$neznama"}},
		{`\{{token}} {{token}}`, "{{token}} runtime", nil},
		{"{{ne platné}} {{", "{{ne platné}} {{", nil},
		{"Kůň {{x}}", "Kůň složka-b", nil},
	}
	for _, tt := range tests {
		got, unres, err := r.Resolve(tt.in)
		if err != nil || got != tt.want || !reflect.DeepEqual(unres, tt.unresolved) {
			t.Errorf("Resolve(%q) = %q %v %v, chci %q %v", tt.in, got, unres, err, tt.want, tt.unresolved)
		}
	}
	if got := r.Unresolved(); !reflect.DeepEqual(got, []string{"$neznama", "nic"}) {
		t.Errorf("Unresolved: %v", got)
	}
	info := r.Explain()
	if len(info) != 5 || info[0].Name != "base" || info[0].Resolved != "https://a.cz/api" || info[0].Source != SourceProject {
		t.Errorf("Explain: %+v", info)
	}

	key := v("key", "tajne123")
	key.Secret = true
	info = New(Scope{Source: SourceEnvironment, Vars: []model.Var{key, v("auth", "Bearer {{key}}")}}).Explain()
	if info[0].Resolved != "Bearer ***" || info[1].Value != "" || info[1].Resolved != "" || !info[1].Secret {
		t.Errorf("maskování: %+v", info)
	}
}

func TestResolveCycleAndDepth(t *testing.T) {
	r := New(Scope{Source: SourceRequest, Vars: []model.Var{v("a", "{{b}}"), v("b", "x{{a}}")}})
	if _, _, err := r.Resolve("{{a}}"); err == nil || !strings.HasPrefix(err.Error(), ErrCycle) {
		t.Errorf("cyklus: %v", err)
	}
	var chain []model.Var
	for i := 0; i < 12; i++ {
		chain = append(chain, v(string(rune('a'+i)), "{{"+string(rune('a'+i+1))+"}}"))
	}
	r = New(Scope{Source: SourceRequest, Vars: chain})
	if _, _, err := r.Resolve("{{a}}"); err == nil || !strings.HasPrefix(err.Error(), ErrCycle) {
		t.Errorf("hloubka: %v", err)
	}
	// stejná proměnná dvakrát vedle sebe není cyklus
	r = New(Scope{Source: SourceRequest, Vars: []model.Var{v("a", "{{b}}{{b}}"), v("b", "1")}})
	if got, _, err := r.Resolve("{{a}}"); got != "11" || err != nil {
		t.Errorf("opakování: %q %v", got, err)
	}
}

func TestDynamic(t *testing.T) {
	r := New()
	got, _, _ := r.Resolve("{{$uuid}} {{$uuid}} {{$timestamp}} {{$timestamp}} {{$randomString}}")
	f := strings.Fields(got)
	if len(f[0]) != 36 || f[0] == f[1] {
		t.Errorf("uuid: %v", f)
	}
	if f[2] != f[3] {
		t.Errorf("timestamp se liší v rámci odeslání: %v", f)
	}
	if len(f[4]) != 16 {
		t.Errorf("randomString: %q", f[4])
	}
	// pojmenovaná proměnná má v rámci odeslání jednu hodnotu
	r = New(Scope{Source: SourceRequest, Vars: []model.Var{v("id", "{{$uuid}}"), v("x", "{{nic}}")}})
	got, unres, _ := r.Resolve("{{id}} {{id}} {{x}}")
	if f = strings.Fields(got); f[0] != f[1] {
		t.Errorf("id se liší: %v", f)
	}
	if _, unres2, _ := r.Resolve("{{x}}"); !reflect.DeepEqual(unres, []string{"nic"}) || !reflect.DeepEqual(unres2, []string{"nic"}) {
		t.Errorf("unresolved z cache: %v %v", unres, unres2)
	}
}

func TestEncodeQueryComponent(t *testing.T) {
	tests := []struct{ in, want string }{
		{"kůň", "k%C5%AF%C5%88"},
		{"a b+c&d=e#f", "a%20b%2Bc%26d%3De%23f"},
		{"už%20kódováno", "u%C5%BE%20k%C3%B3dov%C3%A1no"},
		{"100%", "100%25"},
		{"%zz", "%25zz"},
		{"a/b:c@d,e;f?g", "a/b:c@d,e;f?g"},
	}
	for _, tt := range tests {
		if got := EncodeQueryComponent(tt.in); got != tt.want {
			t.Errorf("EncodeQueryComponent(%q) = %q, chci %q", tt.in, got, tt.want)
		}
	}
}

func TestBuildURL(t *testing.T) {
	r := New(Scope{Source: SourceEnvironment, Vars: []model.Var{
		v("baseUrl", "localhost:8080"), v("id", "a b/č"), v("q", "Žluťoučký kůň"),
	}})
	path := []model.PathParam{{Name: "id", Value: "{{id}}"}, {Name: "fmt", Value: "json"}}
	query := []model.KV{
		{Name: "q", Value: "{{q}}", Enabled: true},
		{Name: "vypnuty", Value: "1"},
		{Name: "flag", Enabled: true},
		{Name: "wsdl", Enabled: true, Bare: true},
		{Name: "pct", Value: "%2F", Enabled: true},
	}
	got, err := BuildURL("{{baseUrl}}/users/:id/x.:fmt/:neni", path, query, r)
	want := "http://localhost:8080/users/a%20b%2F%C4%8D/x.:fmt/:neni?q=%C5%BDlu%C5%A5ou%C4%8Dk%C3%BD%20k%C5%AF%C5%88&flag=&wsdl&pct=%2F"
	if err != nil || got != want {
		t.Errorf("BuildURL\n got %q %v\nwant %q", got, err, want)
	}
	if _, err := BuildURL("{{nic}}/a", nil, nil, r); err == nil || err.Error() != ErrHostUnresolved+": nic" {
		t.Errorf("neznámý host: %v", err)
	}
	if _, err := BuildURL("http://a b/", nil, nil, r); err == nil || !strings.HasPrefix(err.Error(), ErrURLInvalid) {
		t.Errorf("neplatná URL: %v", err)
	}
	if got, err := BuildURL("https://api.cz/u/:id", path[:1], nil, New()); err != nil || got != "https://api.cz/u/%7B%7Bid%7D%7D" {
		t.Errorf("nevyhodnocený path param: %q %v", got, err)
	}
}
