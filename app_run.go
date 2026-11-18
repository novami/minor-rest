package main

import (
	"context"
	"fmt"
	"path"
	"slices"

	"github.com/novami/minor-rest/internal/prepare"
	"github.com/novami/minor-rest/internal/run"
	"github.com/novami/minor-rest/internal/settings"
	"github.com/novami/minor-rest/internal/storage"
)

// Send odešle aktuální stav tabu; blokuje do konce. Chyby odeslání jsou v RunResult.Error.
func (a *App) Send(in run.Input) (run.Result, error) {
	p, err := a.projects.Get(in.ProjectID)
	if err != nil {
		return run.Result{}, err
	}
	folders, err := folderChain(p, in.Rel)
	if err != nil {
		return run.Result{}, err
	}
	prep, err := prepare.Prepare(prepare.Input{
		Request:   in.Request,
		Project:   p.Config(),
		Folders:   folders,
		Defaults:  settings.DefaultHTTP(),
		BaseDir:   p.Root,
		UserAgent: "MinorREST/" + version,
	})
	if err != nil {
		return run.FromResult(in.RunID, nil, err, nil), nil
	}
	res, err := a.engine.Do(context.Background(), in.RunID, prep.Request, prep.Options)
	return run.FromResult(in.RunID, res, err, prep.Unresolved), nil
}

// Cancel zruší běžící odeslání.
func (a *App) Cancel(runID string) { a.engine.Cancel(runID) }

// GetRunBody vrátí tělo odpovědi pro zobrazení (pretty = odsazený JSON).
func (a *App) GetRunBody(runID string, pretty bool) (run.BodyView, error) {
	res, ok := a.engine.Get(runID)
	if !ok {
		return run.BodyView{}, fmt.Errorf("%s: %s", run.ErrNotFound, runID)
	}
	return run.View(res, pretty)
}

// folderChain načte konfigurace nadřazených složek requestu (od kořene).
func folderChain(p *storage.Project, rel string) ([]prepare.Folder, error) {
	var out []prepare.Folder
	for dir := path.Dir(rel); dir != "." && dir != "/" && dir != ""; dir = path.Dir(dir) {
		cfg, err := p.LoadFolderConfig(dir)
		if err != nil {
			return nil, err
		}
		out = append(out, prepare.Folder{Rel: dir, Config: cfg})
	}
	slices.Reverse(out)
	return out, nil
}
