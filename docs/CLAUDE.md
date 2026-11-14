# Terminology service (`../cmd/terms`) — working rules for Claude Code

Import this from the repo-root `../CLAUDE.md` with a line `@docs/CLAUDE.md`.

The terminology service is a Snowstorm-like, multi-code-system terminology server. It is a
**separate service binary** in the CommonPoint monorepo (`github.com/hlogue1/commonpoint`), with
its own database, a gRPC API, and a FHIR R4 terminology facade. It is not a module of the
monolith (`../cmd/srv`, `internal/modules/*`), and modules must not import it. They call it over
gRPC like any other client.

Read, in this order:
1. `ROADMAP.md`: architecture, decisions D1–D13, phases with acceptance criteria
2. `schema-review.md`: required fixes to `migrations/terminology/*` (IDs B1…, C1…, P1…)
3. `migrations/terminology/*.sql`: the existing schema, which is the source of truth for table shapes

## How to work

- One roadmap phase at a time, in order. Within a phase, take the next unchecked item,
  implement it with tests, and tick it in `ROADMAP.md` in the same commit.
- A phase is done only when its **Done when** criteria pass. Say so, then stop for review.
- Schema fixes reference their review ID in the commit message: `fix(terms-schema): B2 staged status + nullable validity`.
- Don't add infrastructure the roadmap doesn't call for (no Elasticsearch, Redis, Kafka, ORMs).
  If you think something is needed, write `docs/terms/adr/NNNN-title.md` and ask.
- Decisions D1–D13 are settled. Challenge one only through an ADR.
- Conventional Commits, scoped: `feat(terms): …`, `feat(terms-snomed): …`, `feat(ctl-terms): …`.

## Where things go

```
api/proto/commonpoint/terminology/v1/*.proto   API source of truth (buf)
api/gen/go/...                                 generated; never hand-edit
cmd/terms/main.go                              server entrypoint (serve; no subcommands besides version)
cmd/ctl/cli/terms/<verb>/command.go            cobra commands = thin AdminService clients
internal/terms/
  server/        gRPC handlers + interceptors (auth, scope authz, audit context, terminology-context, logging)
  authn/         OAuth2 resource server: issuer metadata, JWKS / RFC 7662 introspection, Principal
  authz/         per-RPC scope table (config) + denied-attempt auditing
  audit/         sets terms.actor / request_id / reason per transaction; ListAuditEvents queries
  resolve/       TerminologyContext -> {code_system_id: version_id} (explicit pin, date of service, active)
  provider/      Provider interface, registry, generic table-driven provider
    snomed/ loinc/ rxnorm/ icd10cm/ ... (one package per non-generic system)
  ecl/           ANTLR-generated parser (gen/), AST -> IR, simplifier, executors (sql/)
  search/        query parsing + ranking
  valueset/      compose evaluation, expansion, cache
  conceptmap/    translate, SNOMED extended-map rule evaluator
  loader/        ingest + install jobs; one loader per source format; partition attach/detach
  fhir/          R4 REST facade
  store/         sqlc output + queries/*.sql, pool setup (search_path = terms)
migrations/terminology/NNN_name.sql            tern migrations (own version table)
testdata/terms/                                synthetic fixtures ONLY
tools/terms-fixturegen/                        synthetic RF2/CSV/RRF generators (valid SCTID check digits)
```
Reuse `internal/platform/{cfg,db,grpc,telemetry}`. Extend them rather than building
parallel versions inside `internal/terms`. If a platform package doesn't fit, raise it before
working around it.

## Stack

- Go 1.26, module `github.com/hlogue1/commonpoint`
- gRPC server per D1; protobuf via `buf` (`../buf.yaml`, `buf.gen.yaml` at repo root)
- PostgreSQL **18** (the schema uses `uuidv7()`), database `commonpoint_terms`, schema `terms`
- `pgx/v5` + **sqlc** (queries in `internal/terms/store/queries/*.sql`; sqlc schema = `../migrations/terminology`)
- **tern** for migrations, with version table `terms.schema_version`
- ECL: `github.com/antlr4-go/antlr/v4` with the official SNOMED ECL grammar vendored in `third_party/ecl-grammar/` (commit pinned)
- cobra/viper for `ctl`; `log/slog`; OpenTelemetry through `../internal/platform/telemetry`
- Tests: `testing`, `testcontainers-go` (postgres:18), golden files

## Commands

```sh
podman compose -f deploy/db/compose.yaml up -d
go tool tern migrate -m migrations/terminology -c deploy/db/tern-terms.conf   # create tern-terms.conf in Phase 0
go tool sqlc generate -f internal/terms/store/sqlc.yaml
buf lint && buf breaking --against '.git#branch=main' && buf generate
go run ./cmd/terms
go run ./cmd/ctl terms ingest --system snomed --format rf2 --version 20260901 ...
go test ./internal/terms/... ./cmd/ctl/cli/terms/...
go test -race ./internal/terms/...
go test ./internal/terms/... -run Golden -update   # review the diff before committing
```
If a command doesn't exist yet, creating it is part of Phase 0.

## Non-negotiable rules

1. **Never commit terminology content.** No SNOMED, LOINC, RxNorm, CPT, CDT, MedDRA, NANDA or other
   release files or excerpts, not even "a few rows for a test". Fixtures are synthetic: invented
   descriptions, and SCTIDs from `tools/terms-fixturegen` with valid Verhoeff check digits.
   Well-known metadata IDs as named constants (is-a `116680003`, FSN type, language refsets…) are fine.
   Add `/data/`, `*.zip`, `*.RRF` and `*.rrf` to `../.gitignore` in Phase 0.
2. **Content is immutable per version.** Never `UPDATE` content tables. New content means a new
   `version_id`. Retire with DETACH + DROP (partitioned) or `DELETE … WHERE version_id` (small,
   unpartitioned systems only), following the load/retire order in `02_snomed.sql`.
3. **Every content query is scoped by `version_id`.** A content query without it is a bug. Add a test
   helper that runs `EXPLAIN` and fails if a partitioned table scans more than one partition.
4. **Version resolution goes through `internal/terms/resolve`, always.** No provider picks a version
   itself. `resolve` may call the SQL resolver function (`resolve_version`, review B2/C5), but nothing
   else in the service reads `active_version` or calls `lookup()` / `validate_code()` from
   `15_ix_concept.sql`. Those are for ad-hoc SQL only.
4a. **One active version per code system per instance.** Never add per-environment version selection
   to this service. Environments that need different versions use different terminology environments.
4b. **`version_id` never leaves the instance.** Outward-facing identity (expansion ids, cache keys,
   audit, diff reports) is `(code_system_id, version, source_sha256)`.
5. **Three DB roles:** `cp_terms_migrations` (DDL), `cp_terms_import` (owns content partitions; the
   loader runs as it), and `cp_terms_app` (SELECT on content; DML only on job, activation-log and
   value-set tables; `terms_audit_event` is written only by the SECURITY DEFINER trigger function). Never widen the app role to make something work.
6. **The loader must execute every documented load step**, including the per-partition `module_id`
   FK on `snomed_concept`. Encode the steps as code with a test that asserts the constraint exists
   after install.
7. **Reproducibility:** the same request with the same resolved versions gives byte-identical results,
   including across terminology environments that installed the same source.
   Sort deterministically everywhere (rank, then code). Nothing depends on `now()` or `current_date`
   except resolving a missing `date_of_service`, which is done once, in `resolve`.
8. **Protos first.** Change `.proto`, run `buf lint` + `buf breaking`, then implement. Never break `v1`.
9. **Domain failures aren't RPC errors.** An unknown code gives `result=false` with an `Issue`. RPC
   error codes are for transport, auth and malformed requests.
10. **Auth and audit (ROADMAP D10, D13).**
    - Every RPC except health is authenticated with an OAuth2 bearer token from the external CommonPoint
      clinical IdP, and authorized by the scope listed for that RPC in the scope table. A new RPC without
      a scope table entry must fail closed (a test enumerates every registered RPC).
    - Couple to the IdP through standards only (discovery, JWKS, RFC 7662 introspection). No IdP-specific
      SDKs or IdP code in `internal/terms`. Tests use an in-process fake issuer, never a live IdP.
    - Every mutation runs in a transaction that first calls `audit.Begin(ctx, tx)`, which sets
      `terms.actor`, `terms.request_id` and `terms.reason`. Triggers write `terms_audit_event`; handlers
      never insert audit rows themselves, except for denied attempts (written by the authz interceptor).
    - `terms_audit_event` is append-only. Never add an UPDATE/DELETE path, retention job or "cleanup" for it.
    - Async jobs record the starting principal and run with it as `terms.actor`.
    - This service handles no PHI. Never log tokens, and never log `TranslateRequest.map_context` values.
11. **Licensing gates:** a code system whose `license_tier_id` isn't `open` can't be installed unless
    `code_system_enablement.enabled = true` with a `license_reference`. Searches never return
    disabled systems.
12. `// SPDX-License-Identifier: GPL-3.0-or-later` on every source file (and `--` SQL equivalent).
    Never hand-edit generated code (`api/gen`, sqlc output, ANTLR output).

## SNOMED CT notes

- Load RF2 **Snapshot** files. When layering editions (International + US) into one version, take
  each component's row with the latest `effectiveTime` across the packages.
- The hierarchy is built from **active, inferred** (`900000000000011006`) relationships with
  `typeId = 116680003`. Stated relationships and OWL axioms are out of scope until Phase 9.
- `snomed_concept.preferred_term_en_us` is a display cache. `snomed_language_member` is
  authoritative. Display for other languages/dialects goes through language refset order
  (`en-US` → `900000000000509007` then `900000000000508004`). FSN is never the default display.
- `snomed_closure` is non-reflexive. `<<` = self ∪ descendants. Use `snomed_subsumes()` semantics.
- ECL keywords are case-insensitive, and terms between pipes are ignored when evaluating.

## When unsure

Ask, especially about clinical semantics (how inactive codes behave in a workflow, what counts as
valid for billing on a date of service) and anything touching licensing.
