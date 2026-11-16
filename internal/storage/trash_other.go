//go:build !darwin

package storage

import "errors"

var trashItem = func(string) error { return errors.New("trash not supported") }
