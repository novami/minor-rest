package storage

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"github.com/novami/minor-rest/internal/model"
)

// DefaultCopySuffix se použije, když volající nepředá příponu v jazyce UI.
const DefaultCopySuffix = " kopie"

// CreateFolder vytvoří složku na konci sourozenců.
func (p *Project) CreateFolder(parent, name string) (model.TreeNode, error) {
	return p.create(parent, name, model.KindFolder)
}

// CreateRequest vytvoří nový GET request na konci sourozenců.
func (p *Project) CreateRequest(parent, name string) (model.TreeNode, error) {
	return p.create(parent, name, model.KindRequest)
}

func (p *Project) create(parent, name, kind string) (model.TreeNode, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return model.TreeNode{}, err
	}
	name, err := cleanName(name)
	if err != nil {
		return model.TreeNode{}, err
	}
	if err := p.requireFolder(parent); err != nil {
		return model.TreeNode{}, err
	}
	rel, err := p.freeRel(parent, model.Slugify(name), kind, "")
	if err != nil {
		return model.TreeNode{}, err
	}
	sibs, err := p.siblings(parent, kind)
	if err != nil {
		return model.TreeNode{}, err
	}
	seq := 1
	for _, s := range sibs {
		seq = max(seq, s.Seq+1)
	}
	abs, _ := p.abs(rel)
	if kind == model.KindFolder {
		if err := os.Mkdir(abs, 0o755); err != nil {
			return model.TreeNode{}, fsErr(err)
		}
		err = writeYAML(filepath.Join(abs, model.FolderFile),
			model.FolderConfig{Name: name, Seq: seq, Auth: model.Auth{Type: model.AuthInherit}})
	} else {
		r := model.NewRequest(model.NewID(), name)
		r.Seq = seq
		err = writeYAML(abs, r)
	}
	if err != nil {
		return model.TreeNode{}, err
	}
	return p.node(rel, false)
}

// LoadRequest načte request.
func (p *Project) LoadRequest(rel string) (model.Request, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	var r model.Request
	abs, err := p.requestPath(rel)
	if err == nil {
		err = readYAML(abs, &r)
	}
	return r, err
}

// SaveRequest uloží existující request (soubor se nepřejmenovává, viz Rename).
func (p *Project) SaveRequest(rel string, r model.Request) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return err
	}
	abs, err := p.requestPath(rel)
	if err != nil {
		return err
	}
	if !exists(abs) {
		return errCode(ErrNotFound, rel)
	}
	model.NormalizeNFC(&r)
	return writeYAML(abs, r)
}

// LoadFolderConfig načte `_folder.yaml`.
func (p *Project) LoadFolderConfig(rel string) (model.FolderConfig, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	var cfg model.FolderConfig
	abs, err := p.folderFile(rel)
	if err == nil {
		err = readYAML(abs, &cfg)
	}
	return cfg, err
}

// SaveFolderConfig uloží `_folder.yaml` existující složky.
func (p *Project) SaveFolderConfig(rel string, cfg model.FolderConfig) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return err
	}
	abs, err := p.folderFile(rel)
	if err != nil {
		return err
	}
	if !exists(abs) {
		return errCode(ErrNotFound, rel)
	}
	model.NormalizeNFC(&cfg)
	return writeYAML(abs, cfg)
}

// Rename změní název a přejmenuje soubor/adresář na nový slug. Vrací uzel s novým Rel.
func (p *Project) Rename(rel, newName string) (model.TreeNode, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return model.TreeNode{}, err
	}
	name, err := cleanName(newName)
	if err != nil {
		return model.TreeNode{}, err
	}
	if err := p.requireNode(rel); err != nil {
		return model.TreeNode{}, err
	}
	kind := kindOf(rel)
	if err := p.update(rel, func(n *string, _ *int) { *n = name }); err != nil {
		return model.TreeNode{}, err
	}
	newRel, err := p.freeRel(parentRel(rel), model.Slugify(name), kind, slugOf(rel))
	if err != nil {
		return model.TreeNode{}, err
	}
	if err := p.rename(rel, newRel); err != nil {
		return model.TreeNode{}, err
	}
	return p.node(newRel, true)
}

// Move přesune uzel do složky target na pozici index (mezi sourozenci stejného druhu)
// a přečísluje seq ve zdrojové i cílové složce.
func (p *Project) Move(rel, target string, index int) (model.TreeNode, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return model.TreeNode{}, err
	}
	if err := p.requireNode(rel); err != nil {
		return model.TreeNode{}, err
	}
	if err := p.requireFolder(target); err != nil {
		return model.TreeNode{}, err
	}
	kind := kindOf(rel)
	if kind == model.KindFolder && (target == rel || strings.HasPrefix(target, rel+"/")) {
		return model.TreeNode{}, errCode(ErrMoveIntoSelf, rel)
	}
	oldParent, newRel := parentRel(rel), rel
	if oldParent != target {
		var err error
		if newRel, err = p.freeRel(target, slugOf(rel), kind, ""); err != nil {
			return model.TreeNode{}, err
		}
		if err := p.rename(rel, newRel); err != nil {
			return model.TreeNode{}, err
		}
		if err := p.renumber(oldParent, kind, "", 0); err != nil {
			return model.TreeNode{}, err
		}
	}
	if err := p.renumber(target, kind, newRel, index); err != nil {
		return model.TreeNode{}, err
	}
	return p.node(newRel, true)
}

// Duplicate vytvoří kopii hned za originálem (název + copySuffix, např. „ kopie“ / „ copy“;
// prázdná = DefaultCopySuffix) s novými ID všech requestů.
func (p *Project) Duplicate(rel, copySuffix string) (model.TreeNode, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return model.TreeNode{}, err
	}
	if err := p.requireNode(rel); err != nil {
		return model.TreeNode{}, err
	}
	kind, parent := kindOf(rel), parentRel(rel)
	orig, err := p.node(rel, false)
	if err != nil {
		return model.TreeNode{}, err
	}
	if copySuffix == "" {
		copySuffix = DefaultCopySuffix
	}
	name := orig.Name + copySuffix
	newRel, err := p.freeRel(parent, model.Slugify(name), kind, "")
	if err != nil {
		return model.TreeNode{}, err
	}
	src, _ := p.abs(rel)
	dst, _ := p.abs(newRel)
	if kind == model.KindRequest {
		var r model.Request
		if err := readYAML(src, &r); err != nil {
			return model.TreeNode{}, err
		}
		r.ID, r.Name = model.NewID(), name
		err = writeYAML(dst, r)
	} else {
		err = p.copyFolder(src, dst, name)
	}
	if err != nil {
		return model.TreeNode{}, err
	}
	// pozice hned za originálem
	sibs, err := p.siblings(parent, kind)
	if err != nil {
		return model.TreeNode{}, err
	}
	index := len(sibs)
	for i, s := range sibs {
		if s.Rel == rel {
			index = i + 1
			break
		}
	}
	if err := p.renumber(parent, kind, newRel, index); err != nil {
		return model.TreeNode{}, err
	}
	return p.node(newRel, true)
}

func (p *Project) copyFolder(src, dst, name string) error {
	if err := os.CopyFS(dst, os.DirFS(src)); err != nil {
		return fsErr(err)
	}
	var cfg model.FolderConfig
	cfgPath := filepath.Join(dst, model.FolderFile)
	if err := readYAML(cfgPath, &cfg); err != nil {
		return err
	}
	cfg.Name = name
	if err := writeYAML(cfgPath, cfg); err != nil {
		return err
	}
	return filepath.WalkDir(dst, func(path string, d fs.DirEntry, err error) error {
		if err != nil || d.IsDir() || !strings.HasSuffix(path, model.RequestSuffix) {
			return err
		}
		var r model.Request
		if readYAML(path, &r) != nil {
			return nil // poškozený soubor nech být
		}
		r.ID = model.NewID()
		return writeYAML(path, r)
	})
}

// Delete přesune uzel do Koše, včetně uložených odpovědí jeho requestů.
func (p *Project) Delete(rel string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	if err := p.writable(); err != nil {
		return err
	}
	if err := p.requireNode(rel); err != nil {
		return err
	}
	abs, _ := p.abs(rel)
	ids := requestIDs(abs)
	if err := trashItem(abs); err != nil {
		return errf(ErrTrash, err)
	}
	// ID může sdílet i jiný request (soubor zkopírovaný ve Finderu) – jeho odpovědi nemazat
	inUse := map[string]bool{}
	if len(ids) > 0 {
		for _, id := range requestIDs(p.Root) {
			inUse[id] = true
		}
	}
	for _, id := range ids {
		if inUse[id] {
			continue
		}
		dir := filepath.Join(p.Root, model.ResponsesDir, id)
		if exists(dir) {
			if err := trashItem(dir); err != nil {
				return errf(ErrTrash, err)
			}
		}
	}
	return nil
}

// requestIDs vrátí ID všech requestů v souboru nebo adresáři.
func requestIDs(abs string) []string {
	var ids []string
	filepath.WalkDir(abs, func(path string, d fs.DirEntry, err error) error {
		if err == nil && !d.IsDir() && strings.HasSuffix(path, model.RequestSuffix) {
			var r model.Request
			if readYAML(path, &r) == nil && r.ID != "" && !strings.ContainsAny(r.ID, `/\.`) {
				ids = append(ids, r.ID)
			}
		}
		return nil
	})
	return ids
}

// --- pomocné (volat se zamčeným p.mu) ---

func (p *Project) requestPath(rel string) (string, error) {
	if kindOf(rel) != model.KindRequest {
		return "", errCode(ErrPathInvalid, rel)
	}
	return p.abs(rel)
}

func (p *Project) folderFile(rel string) (string, error) {
	if rel == "" || kindOf(rel) != model.KindFolder {
		return "", errCode(ErrPathInvalid, rel)
	}
	abs, err := p.abs(rel)
	return filepath.Join(abs, model.FolderFile), err
}

// requireFolder ověří, že rel je kořen nebo existující složka.
func (p *Project) requireFolder(rel string) error {
	if rel == "" {
		return nil
	}
	f, err := p.folderFile(rel)
	if err != nil {
		return err
	}
	if !exists(f) {
		return errCode(ErrNotFound, rel)
	}
	return nil
}

// requireNode ověří, že rel je existující request nebo složka (ne kořen).
func (p *Project) requireNode(rel string) error {
	if rel == "" {
		return errCode(ErrPathInvalid, "root")
	}
	if kindOf(rel) == model.KindFolder {
		return p.requireFolder(rel)
	}
	abs, err := p.abs(rel)
	if err != nil {
		return err
	}
	if !exists(abs) {
		return errCode(ErrNotFound, rel)
	}
	return nil
}

// freeRel vrátí volnou cestu pro slug ve složce parent; self (slug) se nepočítá jako kolize.
func (p *Project) freeRel(parent, slug, kind, self string) (string, error) {
	abs, err := p.abs(parent)
	if err != nil {
		return "", err
	}
	taken, err := dirNames(abs)
	if err != nil {
		return "", err
	}
	delete(taken, strings.ToLower(self))
	if parent == "" {
		taken[model.EnvironmentDir] = true
	}
	return joinRel(parent, model.UniqueSlug(slug, has(taken))+suffixFor(kind)), nil
}

func (p *Project) rename(from, to string) error {
	if from == to {
		return nil
	}
	a, _ := p.abs(from)
	b, _ := p.abs(to)
	if err := os.Rename(a, b); err != nil {
		return fsErr(err)
	}
	return nil
}

// update upraví název/seq v souboru uzlu.
func (p *Project) update(rel string, fn func(name *string, seq *int)) error {
	if kindOf(rel) == model.KindRequest {
		abs, _ := p.abs(rel)
		var r model.Request
		if err := readYAML(abs, &r); err != nil {
			return err
		}
		fn(&r.Name, &r.Seq)
		return writeYAML(abs, r)
	}
	f, _ := p.folderFile(rel)
	var cfg model.FolderConfig
	if err := readYAML(f, &cfg); err != nil {
		return err
	}
	fn(&cfg.Name, &cfg.Seq)
	return writeYAML(f, cfg)
}

// renumber přečísluje sourozence druhu kind na 1..n; je-li place neprázdné,
// umístí tento uzel na pozici index. Zapisuje jen změněné.
func (p *Project) renumber(parent, kind, place string, index int) error {
	sibs, err := p.siblings(parent, kind)
	if err != nil {
		return err
	}
	if place != "" {
		var moved *model.TreeNode
		rest := make([]model.TreeNode, 0, len(sibs))
		for i := range sibs {
			if sibs[i].Rel == place {
				moved = &sibs[i]
			} else {
				rest = append(rest, sibs[i])
			}
		}
		if moved != nil {
			index = min(max(index, 0), len(rest))
			sibs = append(rest[:index], append([]model.TreeNode{*moved}, rest[index:]...)...)
		}
	}
	for i, n := range sibs {
		if n.Error != "" || n.Seq == i+1 {
			continue
		}
		seq := i + 1
		if err := p.update(n.Rel, func(_ *string, s *int) { *s = seq }); err != nil {
			return err
		}
	}
	return nil
}
