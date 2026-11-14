# SPDX-License-Identifier: GPL-3.0-or-later

GO          ?= go
BUF         ?= $(GO) tool buf
# Baseline for buf breaking. CI overrides this with the fetched origin/main ref.
BUF_AGAINST ?= .git\#branch=main

.PHONY: ci build vet staticcheck test buf-lint buf-breaking

ci: build vet staticcheck buf-lint buf-breaking

build:
	$(GO) build ./...

vet:
	$(GO) vet ./...

staticcheck:
	$(GO) tool staticcheck ./...

test:
	$(GO) test ./...

buf-lint:
	$(BUF) lint

buf-breaking:
	$(BUF) breaking --against '$(BUF_AGAINST)'
