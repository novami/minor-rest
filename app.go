package main

import (
	"context"
	"sync/atomic"

	"github.com/wailsapp/wails/v2/pkg/runtime"
)

// App holds Wails bindings. Keep it thin – logic belongs to internal/*.
type App struct {
	ctx   context.Context
	dirty atomic.Bool
}

func NewApp() *App {
	return &App{}
}

func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

// beforeClose asks for confirmation when the frontend reports unsaved changes.
func (a *App) beforeClose(ctx context.Context) bool {
	if !a.dirty.Load() {
		return false
	}
	l := menuLabels(systemLang())
	res, err := runtime.MessageDialog(ctx, runtime.MessageDialogOptions{
		Type:          runtime.QuestionDialog,
		Title:         l["closeTitle"],
		Message:       l["closeMessage"],
		Buttons:       []string{l["closeQuit"], l["closeCancel"]},
		DefaultButton: l["closeCancel"],
		CancelButton:  l["closeCancel"],
	})
	if err != nil {
		return false
	}
	return res != l["closeQuit"]
}

// SetDirty is called by the frontend whenever the unsaved-changes state changes.
func (a *App) SetDirty(dirty bool) {
	a.dirty.Store(dirty)
}

// GetVersion returns the application version.
func (a *App) GetVersion() string {
	return version
}

func (a *App) emit(event string) {
	if a.ctx != nil {
		runtime.EventsEmit(a.ctx, event)
	}
}
