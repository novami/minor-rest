package storage

import (
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/novami/minor-rest/internal/model"
)

// LoadTree načte celý strom projektu.
func (p *Project) LoadTree() (model.TreeNode, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.node("", true)
}

// node vrátí uzel na rel; u složky s deep=true i s potomky.
func (p *Project) node(rel string, deep bool) (model.TreeNode, error) {
	if rel == "" {
		n := model.TreeNode{Kind: model.KindFolder, Name: p.cfg.Name}
		var err error
		if deep {
			n.Children, err = p.children("", true)
		}
		return n, err
	}
	if _, err := p.abs(rel); err != nil {
		return model.TreeNode{}, err
	}
	if kindOf(rel) == model.KindRequest {
		return p.requestNode(rel)
	}
	n, err := p.folderNode(rel)
	if err == nil && deep {
		n.Children, err = p.children(rel, true)
	}
	return n, err
}

func (p *Project) requestNode(rel string) (model.TreeNode, error) {
	abs, _ := p.abs(rel)
	n := model.TreeNode{Kind: model.KindRequest, Rel: rel}
	var r model.Request
	if err := readYAML(abs, &r); err != nil {
		if codeOf(err) == ErrNotFound {
			return n, err
		}
		n.Name, n.Error = slugOf(rel), codeOf(err)
		return n, nil
	}
	n.Name, n.Seq, n.ID, n.Method = r.Name, r.Seq, r.ID, r.Method
	return n, nil
}

func (p *Project) folderNode(rel string) (model.TreeNode, error) {
	abs, _ := p.abs(rel)
	n := model.TreeNode{Kind: model.KindFolder, Rel: rel}
	var cfg model.FolderConfig
	if err := readYAML(filepath.Join(abs, model.FolderFile), &cfg); err != nil {
		if codeOf(err) == ErrNotFound {
			return n, err
		}
		n.Name, n.Error = slugOf(rel), codeOf(err)
		return n, nil
	}
	n.Name, n.Seq = cfg.Name, cfg.Seq
	return n, nil
}

// children vrátí seřazené potomky složky: nejdřív složky, pak requesty.
func (p *Project) children(rel string, deep bool) ([]model.TreeNode, error) {
	abs, err := p.abs(rel)
	if err != nil {
		return nil, err
	}
	entries, err := os.ReadDir(abs)
	if err != nil {
		return nil, fsErr(err)
	}
	var folders, reqs []model.TreeNode
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, ".") || strings.HasPrefix(name, "_") {
			continue
		}
		childRel := joinRel(rel, name)
		switch {
		case e.IsDir():
			if rel == "" && name == model.EnvironmentDir {
				continue
			}
			n, err := p.folderNode(childRel)
			if err != nil {
				continue // adresář bez _folder.yaml
			}
			if deep && n.Error == "" {
				if n.Children, err = p.children(childRel, true); err != nil {
					return nil, err
				}
			}
			folders = append(folders, n)
		case strings.HasSuffix(name, model.RequestSuffix):
			if n, err := p.requestNode(childRel); err == nil {
				reqs = append(reqs, n)
			}
		}
	}
	sortNodes(folders)
	sortNodes(reqs)
	return append(folders, reqs...), nil
}

// siblings vrátí seřazené uzly daného druhu ve složce (bez potomků).
func (p *Project) siblings(rel, kind string) ([]model.TreeNode, error) {
	all, err := p.children(rel, false)
	if err != nil {
		return nil, err
	}
	out := all[:0]
	for _, n := range all {
		if n.Kind == kind {
			out = append(out, n)
		}
	}
	return out, nil
}

func sortNodes(ns []model.TreeNode) {
	sort.SliceStable(ns, func(i, j int) bool {
		if (ns[i].Error == "") != (ns[j].Error == "") {
			return ns[i].Error == "" // nečitelné na konec
		}
		if ns[i].Seq != ns[j].Seq {
			return ns[i].Seq < ns[j].Seq
		}
		return strings.ToLower(ns[i].Name) < strings.ToLower(ns[j].Name)
	})
}
