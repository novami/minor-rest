package storage

import (
	"path/filepath"
	"sync"

	"github.com/novami/minor-rest/internal/model"
)

// Registry drží otevřené projekty v pořadí otevření. Bezpečný pro souběžné volání.
type Registry struct {
	mu       sync.Mutex
	projects []*Project
}

// Open otevře projekt v adresáři; už otevřený (stejné ID) vrátí beze změny.
func (r *Registry) Open(root string) (*Project, error) {
	root, err := filepath.Abs(root)
	if err != nil {
		return nil, errf(ErrPathInvalid, err)
	}
	p, err := OpenProject(root)
	if err != nil {
		return nil, err
	}
	return r.Add(p), nil
}

// Add přidá projekt; při shodě ID vrátí ten už otevřený.
func (r *Registry) Add(p *Project) *Project {
	r.mu.Lock()
	defer r.mu.Unlock()
	id := p.Info().ID
	for _, q := range r.projects {
		if q.Info().ID == id {
			return q
		}
	}
	r.projects = append(r.projects, p)
	return p
}

// Get vrátí otevřený projekt podle ID, jinak chybu NOT_FOUND.
func (r *Registry) Get(id string) (*Project, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	for _, p := range r.projects {
		if p.Info().ID == id {
			return p, nil
		}
	}
	return nil, errCode(ErrNotFound, "project "+id)
}

// Close odebere projekt (soubory nemaže).
func (r *Registry) Close(id string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	for i, p := range r.projects {
		if p.Info().ID == id {
			r.projects = append(r.projects[:i], r.projects[i+1:]...)
			return nil
		}
	}
	return errCode(ErrNotFound, "project "+id)
}

// List vrátí informace o otevřených projektech v pořadí otevření.
func (r *Registry) List() []model.ProjectInfo {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]model.ProjectInfo, 0, len(r.projects))
	for _, p := range r.projects {
		out = append(out, p.Info())
	}
	return out
}

// Paths vrátí kořenové adresáře otevřených projektů (pro workspace).
func (r *Registry) Paths() []string {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]string, 0, len(r.projects))
	for _, p := range r.projects {
		out = append(out, p.Root)
	}
	return out
}
