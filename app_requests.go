package main

import "github.com/novami/minor-rest/internal/model"

func (a *App) GetRequest(projectID, rel string) (model.Request, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return model.Request{}, err
	}
	r, err := p.LoadRequest(rel)
	model.FillNilSlices(&r)
	return r, err
}

// SaveRequest uloží obsah requestu; ID, název a pořadí zůstanou z disku.
func (a *App) SaveRequest(projectID, rel string, r model.Request) error {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return err
	}
	return p.SaveRequest(rel, r)
}
