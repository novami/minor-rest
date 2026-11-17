package storage

import (
	"syscall"
	"time"
)

// birthTime vrátí datum vytvoření souboru (nulový čas při chybě).
func birthTime(path string) time.Time {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return time.Time{}
	}
	return time.Unix(st.Birthtimespec.Unix())
}
