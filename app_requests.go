package main

import (
	"github.com/novami/minor-rest/internal/jsonfmt"
	"github.com/novami/minor-rest/internal/model"
	"github.com/wailsapp/wails/v2/pkg/runtime"
)

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

// FormatJSON odsadí JSON tělo (proměnné zůstanou), chyba JSON_INVALID.
func (a *App) FormatJSON(text string) (string, error) { return jsonfmt.Format(text) }

// PickFile nechá vybrat soubor; uvnitř projektu vrátí relativní cestu, jinak absolutní; "" = zrušeno.
func (a *App) PickFile(projectID string) (string, error) {
	p, err := a.projects.Get(projectID)
	if err != nil {
		return "", err
	}
	f, err := runtime.OpenFileDialog(a.ctx, runtime.OpenDialogOptions{DefaultDirectory: p.Root})
	if err != nil || f == "" {
		return "", err
	}
	return p.FileRef(f), nil
}
