// Package prepare složí request k odeslání: dědičnost hlaviček a nastavení, proměnné, URL.
package prepare

import (
	"strings"

	"github.com/novami/minor-rest/internal/httpclient"
	"github.com/novami/minor-rest/internal/model"
	"github.com/novami/minor-rest/internal/vars"
)

// Folder je konfigurace jedné nadřazené složky requestu.
type Folder struct {
	Rel    string
	Config model.FolderConfig
}

// Input je vše, co odeslání potřebuje (načte volající).
type Input struct {
	Request   model.Request
	Project   model.ProjectConfig
	Folders   []Folder // od kořene k nejbližší složce
	Runtime   []model.Var
	Env       []model.Var
	Globals   []model.Var
	Defaults  model.HTTPSettings // globální výchozí nastavení
	BaseDir   string
	UserAgent string
}

// Prepared je request připravený pro httpclient.
type Prepared struct {
	Request    httpclient.Request
	Options    httpclient.Options
	Unresolved []string
}

// autoHeaders lze vypnout řádkem se stejným názvem a enabled: false.
var autoHeaders = []string{"User-Agent", "Accept", "Accept-Encoding", "Content-Type"}

// Prepare vyhodnotí proměnné, složí hlavičky (projekt → složky → request, pozdější úroveň
// přepíše stejný název bez ohledu na velikost písmen) a nastavení (request → projekt → výchozí).
// Auth zatím jen none (ostatní typy se ignorují).
func Prepare(in Input) (Prepared, error) {
	r := vars.New(scopes(in)...)
	req := in.Request

	u, err := vars.BuildURL(req.URL, req.Params.Path, req.Params.Query, r)
	if err != nil {
		return Prepared{}, err
	}

	levels := [][]model.KV{in.Project.Headers}
	for _, f := range in.Folders {
		levels = append(levels, f.Config.Headers)
	}
	levels = append(levels, req.Headers)
	headers, noAuto, err := mergeHeaders(levels, r)
	if err != nil {
		return Prepared{}, err
	}

	body, err := resolveBody(req.Body, r)
	if err != nil {
		return Prepared{}, err
	}

	s := req.Settings.Over(in.Project.Settings).Over(in.Defaults)
	return Prepared{
		Request: httpclient.Request{
			Method:  strings.ToUpper(strings.TrimSpace(req.Method)),
			URL:     u,
			Headers: headers,
			Body:    body,
			BaseDir: in.BaseDir,
			NoAuto:  noAuto,
		},
		Options:    httpclient.OptionsFrom(s, in.UserAgent),
		Unresolved: r.Unresolved(),
	}, nil
}

func scopes(in Input) []vars.Scope {
	s := []vars.Scope{
		{Source: vars.SourceRuntime, Vars: in.Runtime},
		{Source: vars.SourceRequest, Vars: in.Request.Vars},
	}
	for i := len(in.Folders) - 1; i >= 0; i-- {
		s = append(s, vars.Scope{Source: vars.SourceFolder, Ref: in.Folders[i].Rel, Vars: in.Folders[i].Config.Vars})
	}
	return append(s,
		vars.Scope{Source: vars.SourceEnvironment, Vars: in.Env},
		vars.Scope{Source: vars.SourceProject, Vars: in.Project.Vars},
		vars.Scope{Source: vars.SourceGlobal, Vars: in.Globals},
	)
}

// mergeHeaders: názvy výše zmíněné na nižší úrovni (zapnuté i vypnuté) se odstraní,
// zapnuté řádky úrovně se připojí. Vypnutý řádek automatické hlavičky bez zapnutého
// protějšku ji vypne (NoAuto).
func mergeHeaders(levels [][]model.KV, r *vars.Resolver) ([]model.KV, []string, error) {
	var out []model.KV
	disabled := map[string]bool{}
	for _, level := range levels {
		var rows []model.KV
		names := map[string]bool{}
		for _, h := range level {
			name, _, err := r.Resolve(strings.TrimSpace(h.Name))
			if err != nil {
				return nil, nil, err
			}
			if name == "" {
				continue
			}
			key := strings.ToLower(name)
			names[key] = true
			if !h.Enabled {
				disabled[key] = true
				continue
			}
			delete(disabled, key)
			if h.Value, _, err = r.Resolve(h.Value); err != nil {
				return nil, nil, err
			}
			h.Name = name
			rows = append(rows, h)
		}
		kept := out[:0:0]
		for _, h := range out {
			if !names[strings.ToLower(h.Name)] {
				kept = append(kept, h)
			}
		}
		out = append(kept, rows...)
	}
	var noAuto []string
	for _, a := range autoHeaders {
		if disabled[strings.ToLower(a)] {
			noAuto = append(noAuto, a)
		}
	}
	return out, noAuto, nil
}

func resolveBody(b model.Body, r *vars.Resolver) (model.Body, error) {
	var err error
	res := func(s string) string {
		if err != nil {
			return s
		}
		var v string
		v, _, err = r.Resolve(s)
		return v
	}
	out := model.Body{Type: b.Type}
	switch b.Type {
	case model.BodyForm:
		for _, kv := range b.Form {
			if kv.Enabled {
				kv.Name, kv.Value = res(kv.Name), res(kv.Value)
				out.Form = append(out.Form, kv)
			}
		}
	case model.BodyMultipart:
		for _, p := range b.Multipart {
			if p.Enabled {
				p.Name, p.Value, p.Path, p.ContentType = res(p.Name), res(p.Value), res(p.Path), res(p.ContentType)
				out.Multipart = append(out.Multipart, p)
			}
		}
	case model.BodyBinary:
		out.BinaryPath = res(b.BinaryPath)
	case model.BodyNone:
	default:
		out.Raw = res(b.Raw)
	}
	return out, err
}
