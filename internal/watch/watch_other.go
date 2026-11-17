//go:build !darwin

package watch

// Watcher mimo macOS nic nesleduje (aplikace je jen pro macOS).
type Watcher struct{}

func New(onChange func(id string, rels []string), ignoreSelf bool) *Watcher { return &Watcher{} }

func (w *Watcher) Add(id, root string) error { return nil }
func (w *Watcher) Remove(id string)          {}
func (w *Watcher) Close()                    {}
