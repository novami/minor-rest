//go:build !darwin

package storage

import (
	"os"
	"time"
)

// birthTime mimo macOS vrací čas poslední změny.
func birthTime(path string) time.Time {
	fi, err := os.Stat(path)
	if err != nil {
		return time.Time{}
	}
	return fi.ModTime()
}
