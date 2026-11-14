# SPDX-License-Identifier: GPL-3.0-or-later

GO          ?= go
BUF         ?= $(GO) tool buf
# Baseline for buf breaking. CI overrides this with the fetched origin/main ref.
BUF_AGAINST ?= .git\#branch=main

.PHONY: ci build vet staticcheck test test-db buf-lint buf-breaking

ci: build vet staticcheck buf-lint buf-breaking

build:
	$(GO) build ./...

vet:
	$(GO) vet ./...

staticcheck:
	$(GO) tool staticcheck ./...

test:
	$(GO) test ./...

# Database tests on a throwaway PostgreSQL 18 container (testcontainers-go). Under Podman,
# DOCKER_HOST is pointed at the machine's socket and Ryuk (the reaper) is disabled.
DB_TEST_PKGS ?= ./internal/platform/db/... ./internal/terms/store/...
PODMAN_SOCK  := $(shell command -v podman >/dev/null 2>&1 && podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}' 2>/dev/null)

test-db:
ifneq ($(PODMAN_SOCK),)
	DOCKER_HOST=$${DOCKER_HOST:-unix://$(PODMAN_SOCK)} TESTCONTAINERS_RYUK_DISABLED=true $(GO) test $(DB_TEST_PKGS)
else
	$(GO) test $(DB_TEST_PKGS)
endif

buf-lint:
	$(BUF) lint

buf-breaking:
	$(BUF) breaking --against '$(BUF_AGAINST)'
