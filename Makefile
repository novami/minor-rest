export PATH := $(HOME)/go/bin:$(PATH)
export CGO_CFLAGS := -mmacosx-version-min=13.0
export CGO_LDFLAGS := -mmacosx-version-min=13.0

VERSION ?= dev
LDFLAGS := -X main.version=$(VERSION)

.PHONY: dev build test check

dev:
	wails dev

build:
	wails build -platform darwin/arm64 -clean -ldflags "$(LDFLAGS)"

test:
	go vet ./internal/...
	go test ./internal/...

check:
	cd frontend && npm run check
