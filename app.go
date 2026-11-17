package main

import (
	"context"
	"strings"
	"sync"
	"sync/atomic"

	"github.com/wailsapp/wails/v2/pkg/runtime"

	"github.com/novami/minor-rest/internal/model"
	"github.com/novami/minor-rest/internal/settings"
	"github.com/novami/minor-rest/internal/storage"
	"github.com/novami/minor-rest/internal/watch"
)

// App holds Wails bindings. Keep it thin – logic belongs to internal/*.
type App struct {
	ctx      context.Context
	dirty    atomic.Bool
	quitting atomic.Bool
	projects storage.Registry
	appDir   string
	watcher  *watch.Watcher

	wsMu sync.Mutex
	ws   settings.Workspace
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
	a.watcher = watch.New(func(id string, rels []string) {
		a.emit("tree:changed", map[string]string{"projectID": id})
		for _, rel := range rels {
			if strings.HasSuffix(rel, model.RequestSuffix) {
				a.emit("request:changedOnDisk", map[string]string{"projectID": id, "rel": rel})
			}
		}
	}, true)
	a.loadWorkspace()
}

func (a *App) shutdown(ctx context.Context) {
	if a.watcher != nil {
		a.watcher.Close()
	}
}

// beforeClose se při neuložených změnách zeptá: Uložit (uloží frontend a zavolá Quit) / Neukládat / Zrušit.
func (a *App) beforeClose(ctx context.Context) bool {
	if a.quitting.Load() || !a.dirty.Load() {
		return false
	}
	l := menuLabels(systemLang())
	res, err := runtime.MessageDialog(ctx, runtime.MessageDialogOptions{
		Type:          runtime.QuestionDialog,
		Title:         l["closeTitle"],
		Message:       l["closeMessage"],
		Buttons:       []string{l["closeSave"], l["closeQuit"], l["closeCancel"]},
		DefaultButton: l["closeSave"],
		CancelButton:  l["closeCancel"],
	})
	switch {
	case err != nil, res == l["closeQuit"]:
		return false
	case res == l["closeSave"]:
		a.emit("app:saveAndQuit")
	}
	return true
}

// Quit ukončí aplikaci bez dalšího dotazu (frontend ji volá po uložení všech tabů).
func (a *App) Quit() {
	a.quitting.Store(true)
	runtime.Quit(a.ctx)
}

// SetDirty is called by the frontend whenever the unsaved-changes state changes.
func (a *App) SetDirty(dirty bool) {
	a.dirty.Store(dirty)
}

// GetVersion returns the application version.
func (a *App) GetVersion() string {
	return version
}

func (a *App) emit(event string, data ...any) {
	if a.ctx != nil {
		runtime.EventsEmit(a.ctx, event, data...)
	}
}
