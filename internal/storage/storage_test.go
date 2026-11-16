package storage

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/novami/minor-rest/internal/model"
)

func newProject(t *testing.T) *Project {
	t.Helper()
	trash := t.TempDir()
	trashItem = func(path string) error {
		return os.Rename(path, filepath.Join(trash, filepath.Base(path)))
	}
	p, err := CreateProject(t.TempDir(), "Můj projekt")
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func must[T any](v T, err error) T {
	if err != nil {
		panic(err)
	}
	return v
}

// names vrátí názvy uzlů oddělené čárkou.
func names(ns []model.TreeNode) string {
	var out []string
	for _, n := range ns {
		out = append(out, n.Name)
	}
	return strings.Join(out, ",")
}

func TestCreateAndTree(t *testing.T) {
	p := newProject(t)
	if filepath.Base(p.Root) != "muj-projekt" {
		t.Errorf("root: %s", p.Root)
	}
	gi, _ := os.ReadFile(filepath.Join(p.Root, ".gitignore"))
	if string(gi) != ".responses/\n" {
		t.Errorf(".gitignore: %q", gi)
	}
	f := must(p.CreateFolder("", "Uživatelé"))
	must(p.CreateFolder(f.Rel, "Detail"))
	r := must(p.CreateRequest(f.Rel, "Seznam"))
	must(p.CreateRequest(f.Rel, "Seznam")) // kolize → seznam-2
	must(p.CreateRequest("", "Kořenový"))
	os.Mkdir(filepath.Join(p.Root, "bez-configu"), 0o755) // ignoruje se
	os.WriteFile(filepath.Join(p.Root, "rozbity.req.yaml"), []byte("name: [x"), 0o644)

	if r.Rel != "uzivatele/seznam.req.yaml" || r.ID == "" || r.Method != model.MethodGet {
		t.Errorf("request: %+v", r)
	}
	tree := must(p.LoadTree())
	if got := names(tree.Children); got != "Uživatelé,Kořenový,rozbity" {
		t.Errorf("kořen: %s", got)
	}
	if tree.Children[2].Error != model.ErrYAMLInvalid {
		t.Errorf("rozbitý: %+v", tree.Children[2])
	}
	u := tree.Children[0]
	if got := names(u.Children); got != "Detail,Seznam,Seznam" || u.Children[2].Rel != "uzivatele/seznam-2.req.yaml" {
		t.Errorf("uživatelé: %+v", u.Children)
	}

	q, err := OpenProject(p.Root)
	if err != nil || q.Info().ID != p.Info().ID || q.Info().ReadOnly {
		t.Errorf("open: %+v %v", q, err)
	}
}

func TestRenameMoveDuplicateDelete(t *testing.T) {
	p := newProject(t)
	a := must(p.CreateFolder("", "A"))
	b := must(p.CreateFolder("", "B"))
	r1 := must(p.CreateRequest(a.Rel, "Jedna"))
	must(p.CreateRequest(b.Rel, "Dva"))
	must(p.CreateRequest(b.Rel, "Tři"))

	// přejmenování s diakritikou
	r1 = must(p.Rename(r1.Rel, "Příliš žluťoučký kůň"))
	if r1.Rel != "a/prilis-zlutoucky-kun.req.yaml" || r1.Name != "Příliš žluťoučký kůň" {
		t.Errorf("rename: %+v", r1)
	}
	b = must(p.Rename(b.Rel, "Béčko"))
	if b.Rel != "becko" || len(b.Children) != 2 {
		t.Errorf("rename složky: %+v", b)
	}

	// přesun mezi složky na začátek
	r1 = must(p.Move(r1.Rel, b.Rel, 0))
	if r1.Rel != "becko/prilis-zlutoucky-kun.req.yaml" {
		t.Errorf("move: %+v", r1)
	}
	kids := must(p.LoadTree()).Children[1].Children
	if got := names(kids); got != "Příliš žluťoučký kůň,Dva,Tři" {
		t.Errorf("pořadí po přesunu: %s", got)
	}
	for i, k := range kids {
		if k.Seq != i+1 {
			t.Errorf("seq %s = %d", k.Name, k.Seq)
		}
	}
	// přeřazení ve stejné složce na konec
	must(p.Move(r1.Rel, b.Rel, 99))
	if got := names(must(p.LoadTree()).Children[1].Children); got != "Dva,Tři,Příliš žluťoučký kůň" {
		t.Errorf("přeřazení: %s", got)
	}
	if _, err := p.Move(b.Rel, b.Rel, 0); err == nil || codeOf(err) != ErrMoveIntoSelf {
		t.Errorf("move do sebe: %v", err)
	}

	// duplikace složky – hned za originál, nová ID
	d := must(p.Duplicate(a.Rel, ""))
	if d.Name != "A kopie" || d.Rel != "a-kopie" {
		t.Errorf("duplikát: %+v", d)
	}
	dup := must(p.Duplicate("becko/dva.req.yaml", " copy"))
	tree := must(p.LoadTree())
	if got := names(tree.Children); got != "A,A kopie,Béčko" {
		t.Errorf("po duplikaci: %s", got)
	}
	if got := names(tree.Children[2].Children); got != "Dva,Dva copy,Tři,Příliš žluťoučký kůň" {
		t.Errorf("duplikát requestu: %s", got)
	}
	orig := must(p.LoadRequest("becko/dva.req.yaml"))
	if dup.ID == "" || dup.ID == orig.ID {
		t.Errorf("ID duplikátu: %s vs %s", dup.ID, orig.ID)
	}

	// smazání nesmí vzít odpovědi requestu se stejným ID jinde (kopie z Finderu)
	finderCopy := must(p.CreateRequest(a.Rel, "Kopie z Finderu"))
	fc := must(p.LoadRequest(finderCopy.Rel))
	fc.ID = orig.ID
	must(0, p.SaveRequest(finderCopy.Rel, fc))
	resp := filepath.Join(p.Root, model.ResponsesDir, orig.ID)
	os.MkdirAll(resp, 0o755)
	if err := p.Delete("becko/dva.req.yaml"); err != nil || !exists(resp) {
		t.Errorf("sdílené ID: %v, odpovědi existují=%v", err, exists(resp))
	}
	must(0, p.Delete(finderCopy.Rel))

	// smazání včetně uložených odpovědí
	tri := must(p.LoadRequest("becko/tri.req.yaml"))
	resp = filepath.Join(p.Root, model.ResponsesDir, tri.ID)
	os.MkdirAll(resp, 0o755)
	if err := p.Delete("becko"); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(p.Root, "becko")) || exists(resp) {
		t.Error("smazané položky zůstaly")
	}
}

func TestSaveRequestAndGuards(t *testing.T) {
	p := newProject(t)
	n := must(p.CreateRequest("", "X"))
	r := must(p.LoadRequest(n.Rel))
	r.URL = "{{baseUrl}}/a"
	if err := p.SaveRequest(n.Rel, r); err != nil {
		t.Fatal(err)
	}
	if got := must(p.LoadRequest(n.Rel)); got.URL != r.URL {
		t.Errorf("url: %q", got.URL)
	}
	for _, rel := range []string{"../venku.req.yaml", "/abs.req.yaml", "a/../b.req.yaml"} {
		if _, err := p.LoadRequest(rel); err == nil || codeOf(err) != ErrPathInvalid {
			t.Errorf("%s: %v", rel, err)
		}
	}
	if err := p.SaveRequest("neni.req.yaml", r); codeOf(err) != ErrNotFound {
		t.Errorf("save neexistujícího: %v", err)
	}
	if _, err := p.CreateFolder("", "  "); codeOf(err) != ErrNameEmpty {
		t.Errorf("prázdný název: %v", err)
	}
	// složka „environments“ v kořeni nesmí kolidovat s adresářem prostředí
	if f := must(p.CreateFolder("", "Environments")); f.Rel != "environments-2" {
		t.Errorf("environments: %s", f.Rel)
	}

	// vyšší formatVersion → jen pro čtení
	cfg := p.Config()
	cfg.FormatVersion = model.FormatVersion + 1
	writeYAML(filepath.Join(p.Root, model.ProjectFile), cfg)
	q := must(OpenProject(p.Root))
	if _, err := q.CreateRequest("", "Y"); codeOf(err) != ErrReadOnly {
		t.Errorf("read-only: %v", err)
	}
	cfg.IgnoreResponsesInGit = false
	if err := p.SaveConfig(cfg); err != nil {
		t.Fatal(err)
	}
	if gi, _ := os.ReadFile(filepath.Join(p.Root, ".gitignore")); len(gi) != 0 {
		t.Errorf(".gitignore: %q", gi)
	}
}
