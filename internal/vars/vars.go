// Package vars vyhodnocuje proměnné `{{nazev}}` (scope, dynamické proměnné, rekurze).
package vars

import (
	"crypto/rand"
	"fmt"
	"math/big"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"

	"github.com/novami/minor-rest/internal/model"
)

// Kódy chyb.
const (
	ErrCycle = "VAR_CYCLE"
)

// Zdroje proměnných (VarInfo.Source).
const (
	SourceRuntime     = "runtime"
	SourceRequest     = "request"
	SourceFolder      = "folder"
	SourceEnvironment = "environment"
	SourceProject     = "project"
	SourceGlobal      = "global"
	SourceDynamic     = "dynamic"
)

const maxDepth = 10

// Scope je sada proměnných jednoho zdroje. U složky Ref = rel složky.
type Scope struct {
	Source string
	Ref    string
	Vars   []model.Var
}

// VarInfo popisuje platnou (vítěznou) proměnnou pro UI.
type VarInfo struct {
	Name     string `json:"name" yaml:"name"`
	Value    string `json:"value" yaml:"value"`       // hodnota tak, jak je zapsaná
	Resolved string `json:"resolved" yaml:"resolved"` // po vyhodnocení vnořených proměnných
	Source   string `json:"source" yaml:"source"`
	Ref      string `json:"ref,omitempty" yaml:"ref,omitempty"`
	Secret   bool   `json:"secret,omitempty" yaml:"secret,omitempty"`
}

type cached struct {
	val        string
	unresolved []string
}

type entry struct {
	v     model.Var
	scope *Scope
}

// Resolver vyhodnocuje proměnné pro jedno odeslání: časové dynamické proměnné a hodnoty
// pojmenovaných proměnných jsou pevné (`{{id}}` s `{{$uuid}}` dá všude stejné UUID),
// přímý výskyt `{{$uuid}}` je pokaždé nový.
type Resolver struct {
	vars       map[string]entry
	cache      map[string]cached // pojmenovaná proměnná má v rámci odeslání jednu hodnotu
	now        time.Time
	unresolved map[string]bool
}

// New vytvoří resolver; scopes v pořadí priority (první vyhrává):
// runtime → request → složky (nejbližší první) → prostředí → projekt → globální.
func New(scopes ...Scope) *Resolver {
	r := &Resolver{vars: map[string]entry{}, cache: map[string]cached{}, now: time.Now(), unresolved: map[string]bool{}}
	for i := range scopes {
		for _, v := range scopes[i].Vars {
			if !v.Enabled || v.Name == "" {
				continue
			}
			if _, ok := r.vars[v.Name]; !ok {
				r.vars[v.Name] = entry{v, &scopes[i]}
			}
		}
	}
	return r
}

// Resolve nahradí proměnné v s. Neznámé ponechá jako literál a vrátí jejich názvy.
// Cyklus nebo hloubka > 10 → chyba VAR_CYCLE.
func (r *Resolver) Resolve(s string) (string, []string, error) {
	var unresolved []string
	out, err := r.resolve(s, nil, &unresolved)
	for _, n := range unresolved {
		r.unresolved[n] = true
	}
	return out, unresolved, err
}

// Unresolved vrátí seřazené názvy všech dosud nevyhodnocených proměnných.
func (r *Resolver) Unresolved() []string {
	out := make([]string, 0, len(r.unresolved))
	for n := range r.unresolved {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// Masked nahrazuje hodnoty tajných proměnných v Explain.
const Masked = "***"

// Explain vrátí platné proměnné seřazené dle názvu (chyby vyhodnocení se ignorují).
// Tajné hodnoty se nevrací (UI je získá přes RevealSecret) a v Resolved jiných proměnných se maskují.
func (r *Resolver) Explain() []VarInfo {
	var secrets []string
	for _, e := range r.vars {
		if e.v.Secret && e.v.Value != "" {
			secrets = append(secrets, e.v.Value)
		}
	}
	out := make([]VarInfo, 0, len(r.vars))
	for name, e := range r.vars {
		info := VarInfo{Name: name, Source: e.scope.Source, Ref: e.scope.Ref, Secret: e.v.Secret}
		if !e.v.Secret {
			var ignored []string
			info.Value = e.v.Value
			info.Resolved, _ = r.resolve(e.v.Value, []string{name}, &ignored)
			for _, s := range secrets {
				info.Resolved = strings.ReplaceAll(info.Resolved, s, Masked)
			}
		}
		out = append(out, info)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

func (r *Resolver) resolve(s string, stack []string, unresolved *[]string) (string, error) {
	if !strings.Contains(s, "{{") {
		return s, nil
	}
	var b strings.Builder
	for i := 0; i < len(s); {
		if strings.HasPrefix(s[i:], `\{{`) {
			b.WriteString("{{")
			i += 3
			continue
		}
		if !strings.HasPrefix(s[i:], "{{") {
			b.WriteByte(s[i])
			i++
			continue
		}
		end := strings.Index(s[i+2:], "}}")
		if end < 0 {
			b.WriteString(s[i:])
			break
		}
		raw := s[i : i+2+end+2]
		name := strings.TrimSpace(s[i+2 : i+2+end])
		i += len(raw)
		val, ok, err := r.lookup(name, stack, unresolved)
		if err != nil {
			return "", err
		}
		if !ok {
			if validName(strings.TrimPrefix(name, "$")) {
				*unresolved = appendUnique(*unresolved, name)
			}
			b.WriteString(raw)
			continue
		}
		b.WriteString(val)
	}
	return b.String(), nil
}

func (r *Resolver) lookup(name string, stack []string, unresolved *[]string) (string, bool, error) {
	if strings.HasPrefix(name, "$") {
		v, ok := r.dynamic(name)
		return v, ok, nil
	}
	if !validName(name) {
		return "", false, nil
	}
	e, ok := r.vars[name]
	if !ok {
		return "", false, nil
	}
	for _, s := range stack {
		if s == name {
			return "", false, fmt.Errorf("%s: %s", ErrCycle, strings.Join(append(stack, name), " → "))
		}
	}
	if len(stack) >= maxDepth {
		return "", false, fmt.Errorf("%s: %s", ErrCycle, strings.Join(append(stack, name), " → "))
	}
	if c, ok := r.cache[name]; ok {
		for _, n := range c.unresolved {
			*unresolved = appendUnique(*unresolved, n)
		}
		return c.val, true, nil
	}
	var inner []string
	v, err := r.resolve(e.v.Value, append(stack[:len(stack):len(stack)], name), &inner)
	if err != nil {
		return "", false, err
	}
	r.cache[name] = cached{v, inner}
	for _, n := range inner {
		*unresolved = appendUnique(*unresolved, n)
	}
	return v, true, nil
}

func (r *Resolver) dynamic(name string) (string, bool) {
	switch name {
	case "$uuid":
		return uuid.NewString(), true
	case "$ulid":
		return model.NewID(), true
	case "$timestamp":
		return strconv.FormatInt(r.now.Unix(), 10), true
	case "$timestampMs":
		return strconv.FormatInt(r.now.UnixMilli(), 10), true
	case "$isoTimestamp":
		return r.now.UTC().Format("2006-01-02T15:04:05.000Z"), true
	case "$randomInt":
		n, _ := rand.Int(rand.Reader, big.NewInt(1001))
		return n.String(), true
	case "$randomString":
		return randomString(16), true
	}
	return "", false
}

const alnum = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

func randomString(n int) string {
	b := make([]byte, n)
	for i := range b {
		k, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alnum))))
		b[i] = alnum[k.Int64()]
	}
	return string(b)
}

// validName: [A-Za-z0-9_.-]+
func validName(s string) bool {
	if s == "" {
		return false
	}
	for _, c := range s {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '.' || c == '-') {
			return false
		}
	}
	return true
}

func appendUnique(list []string, s string) []string {
	for _, x := range list {
		if x == s {
			return list
		}
	}
	return append(list, s)
}
