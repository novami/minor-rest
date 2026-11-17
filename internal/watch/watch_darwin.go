package watch

import (
	"path/filepath"
	"slices"
	"strings"
	"sync"

	"github.com/fsnotify/fsevents"
)

// Watcher sleduje projekty přes FSEvents (jeden rekurzivní stream na projekt).
// onChange dostane ID projektu a změněné cesty (nil = rozsah neznámý, načíst vše).
type Watcher struct {
	mu         sync.Mutex
	streams    map[string]*fsevents.EventStream
	onChange   func(id string, rels []string)
	ignoreSelf bool
}

// New vytvoří watcher. ignoreSelf potlačí změny provedené tímto procesem
// (vlastní zápisy aplikace); testy ho vypínají.
func New(onChange func(id string, rels []string), ignoreSelf bool) *Watcher {
	return &Watcher{streams: map[string]*fsevents.EventStream{}, onChange: onChange, ignoreSelf: ignoreSelf}
}

// Add začne sledovat kořen projektu; už sledovaný projekt nejdřív odebere.
func (w *Watcher) Add(id, root string) error {
	w.Remove(id)
	if r, err := filepath.EvalSymlinks(root); err == nil {
		root = r // FSEvents hlásí kanonické cesty (/private/tmp …)
	}
	flags := fsevents.FileEvents
	if w.ignoreSelf {
		flags |= fsevents.IgnoreSelf
	}
	es := &fsevents.EventStream{
		Paths:   []string{root},
		Latency: Latency,
		Flags:   flags,
		Events:  make(chan []fsevents.Event, 8),
	}
	if err := es.Start(); err != nil {
		return err
	}
	go w.loop(id, root, es.Events)
	w.mu.Lock()
	w.streams[id] = es
	w.mu.Unlock()
	return nil
}

func (w *Watcher) loop(id, root string, events <-chan []fsevents.Event) {
	const rescan = fsevents.MustScanSubDirs | fsevents.KernelDropped | fsevents.UserDropped | fsevents.RootChanged
	for batch := range events {
		var rels []string
		all := false
		for _, e := range batch {
			if e.Flags&rescan != 0 {
				all = true
				continue
			}
			path := e.Path
			if !strings.HasPrefix(path, "/") {
				path = "/" + path
			}
			if rel, ok := relOf(root, path); ok && !slices.Contains(rels, rel) {
				rels = append(rels, rel)
			}
		}
		switch {
		case all:
			w.onChange(id, nil)
		case len(rels) > 0:
			w.onChange(id, rels)
		}
	}
}

// Remove přestane sledovat projekt.
func (w *Watcher) Remove(id string) {
	w.mu.Lock()
	es := w.streams[id]
	delete(w.streams, id)
	w.mu.Unlock()
	if es != nil {
		es.Stop()
		close(es.Events) // po Stop už callback nic nepošle; ukončí loop
	}
}

// Close zastaví všechny streamy.
func (w *Watcher) Close() {
	w.mu.Lock()
	ids := make([]string, 0, len(w.streams))
	for id := range w.streams {
		ids = append(ids, id)
	}
	w.mu.Unlock()
	for _, id := range ids {
		w.Remove(id)
	}
}
