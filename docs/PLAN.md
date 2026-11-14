# CommonPoint terminology service: development plan

Status: v3 · 2026-11-13 · based on the repository at commit `c18c8bf` plus untracked `api/`
Owner: Harley · Executed with Claude Code (see `/CLAUDE.md`)

## Scope

**In scope:** the terminology service (`cmd/terms`), its schema (`migrations/terminology/`), its admin CLI
(`cmd/ctl terms …`), its API (`api/proto/commonpoint/terminology/`), the `terms-db` container (PostgreSQL 18),
the shared Go plumbing it needs (`internal/platform/{cfg,db,grpc,telemetry}`), **OAuth2 token validation**
against the CommonPoint clinical IdP, and an **append-only audit trail** of who changed what and when.

**Out of scope:** the core migrations (`migrations/##-cp-core-*.sql`), build (`ctl build`, the `build`
schema, the Doltgres build-db), and the IdP itself (`deploy/id`, `cmd/idp`). The IdP runs as an outside
service; the terms service is only an OAuth2 resource server for it (ROADMAP D10). **No Doltgres** anywhere
in the terminology service (D12).

Detailed per-phase tasks live in `docs/terms/ROADMAP.md`. This plan sequences them, folds in the verified
findings below, and says what to do first.

---

## 1. Where things stand

| Area | State |
|---|---|
| `migrations/terminology/` (15 files, ~100 tables) | Applies cleanly; down → up round-trips with 0 leftovers (verified). Versioning implemented: staged/active/superseded/retired, date-of-service validity + trigger, `activate_version()` with ready-check and range trimming. All big families are partitioned. |
| `cmd/terms` | `package main` only, with no `func main`. `go build ./...` fails (on the other `cmd/*` stubs too). |
| `cmd/ctl terms` | 8 verbs wired in cobra (`activate clean impact ingest install package rollback validate`), no behavior. `package` = "Export terminology artifact". |
| `internal/platform/*` | Empty directories. |
| `api/proto/…/terminology/v1` | Draft protos, compile, **untracked**; no `buf.yaml` in the repo. |
| `deploy/db` `terms-db` | `postgresql:latest`. The schema needs **PG 18** (`uuidv7()`). |
| Tests / CI | None. |

---

## 2. Findings (verified by running)

I applied every terminology migration to a scratch PostgreSQL 16 with a `uuidv7()` shim and ran behavior
tests. The scripts and output are in `docs/plan-evidence/`. ✅ = reproduced, 👁 = from reading.

| ID | Finding | Fix |
|---|---|---|
| **T1** ✅ | **The retire recipe in `002_snomed.sql` fails as described.** Detaching every partition first and dropping afterwards fails: a detached partition keeps its FK, now pointing at the *parent* table, so the next DETACH is rejected. A plain `DROP TABLE` on a referenced, attached partition also fails. | Per table, in reverse dependency order: `DETACH PARTITION` → `DROP TABLE` immediately, then the next table (verified). Fix the comment and implement it once in the loader. |
| **T2** ✅ | **`DELETE FROM code_system_version` silently cascades through partitioned families**, deleting row by row and leaving empty partitions attached. On a real edition that's millions of deletes. | `BEFORE DELETE` trigger refusing deletion while any partition for that version exists ("retire via ctl terms clean"). |
| **T3** ✅ | **A date-of-service rollback can't be undone.** Activating ICD-10-CM `2027-04` permanently trims `2027`'s range. Re-activating `2027` leaves `2027-04` superseded but valid, so May 2027 still resolves to the April update. | Add an immutable `published_validity`. `activate_version()` restores the target's range from it before trimming the others. Add `rollback_version(code_system_id)`, which returns the current version to `staged` and re-activates the previous one from the activation log. |
| **T4** ✅ | `version_for_date('icd10cm', d)` with an untyped literal picks the URI overload and returns NULL. | Rename to `version_for_date_by_id` / `version_for_date_by_uri`. |
| **T5** 👁 | **No way to tell who changed what, or when.** No `source_sha256`, `validated_at`, `activated_at/by`, no activation history, no audit table. `activate_version()` and direct edits to `code_system_enablement` leave no trace. | Add the version columns + `version_activation_log` + the append-only `terms_audit_event` with capture triggers (ROADMAP D13). `UNIQUE (code_system_id, version, source_sha256)`. |
| **T6** 👁 | No roles or grants. `tern.conf` uses the default version table. | Roles migration: `cp_terms_migrations`, `cp_terms_import` (owns content partitions), `cp_terms_app` (SELECT on content; versions change only through the functions). Explicit `version_table` in `tern.conf`. |
| **T7** ✅ | `code_system_enablement` is never seeded, so `lookup()` returns nothing until rows exist. | Seed `open`-tier systems as enabled. Restricted tiers stay disabled until enabled with a `license_reference`. |
| **T8** 👁 | Still open from the earlier review: SNOMED `effective_time` (C6), RxNorm PSN/TMSY synonyms (C7), CPT `MAAA` (C8), HCPCS D-codes vs CDT (C9), ICD-10-CM sections (C10), LOINC hierarchy (C11), `loinc_panel_member` rekey (C12), plus 6 `TODO(verify)` notes. | C6 + C12 in M1. The rest per code system in M6. |

Repo hygiene that blocks the terms work:

| ID | Finding | Fix |
|---|---|---|
| **R1** | `cmd/*/main.go` have no `func main`, so `go build ./...` fails (couldn't build here: no Go 1.26 toolchain download, but a `main` package without `main()` doesn't compile). | Minimal `main()` in every `cmd/*` so the module builds; real code only in `cmd/terms`. |
| **R2** | Every `go.mod` requirement is `// indirect`. | `go mod tidy`. |
| **R3** | `api/` and `go.sum` untracked; `api/proto/.DS_Store`. | Commit them with `buf.yaml`/`buf.gen.yaml`; `.gitignore`: `.DS_Store`, `.idea/`, `/data/`, `*.zip`, `*.RRF`. |
| **R4** | `terms-db` uses `postgresql:latest`. | Pin to a PostgreSQL 18.x tag. |
| **R6** | The `ctl` root declares `Args: ExactArgs(1)` with no `Run`; `ingest` uses `--termSystem`. | Drop the root `Args`; kebab-case flags (`--system`, `--format`, `--version`). |

---

## 3. Shape of the service

```
 clients (GTK, Flex, Angular, cmd/srv)        ctl terms <verb>
              │ gRPC                                │ gRPC (AdminService)
              ▼                                     ▼
 ┌──────────────────────────── cmd/terms ─────────────────────────────┐
 │ interceptors: OAuth2 bearer → scope check → audit ctx → resolve    │
 │ TerminologyService · SnomedService · AdminService · /fhir (later)  │
 │ providers (snomed, loinc, rxnorm, icd10cm, …, generic) · ecl ·     │
 │ search · valueset · conceptmap · loader jobs                       │
 └───────────────────────────────┬────────────────────────────────────┘
                                 │ pgx (roles: app / import / migrations)
                         terms-db (PostgreSQL 18)          CommonPoint clinical IdP
                         incl. terms_audit_event   ◀── JWKS / introspection (outside service)
```
Decisions D1–D13 in `docs/terms/ROADMAP.md`. D10 (OAuth2 resource server), D12 (PostgreSQL 18 only, no
Doltgres) and D13 (audit trail) were added or updated for this version.

### What the IdP needs to provide (confirm before M2)
The terms service depends on the IdP only through these standard contracts. Confirm each one with the IdP design:
1. **Issuer metadata** at `/.well-known/openid-configuration` (or RFC 8414) with `jwks_uri`, and `introspection_endpoint` if tokens are opaque.
2. **Access token format.** JWT (RFC 9068) is preferred: no network call per request, and identity is in the token. Opaque tokens work too, but need introspection credentials for `cmd/terms`.
3. **Audience.** Tokens for this service carry `aud = commonpoint-terms` (or a resource indicator, RFC 8707).
4. **Scopes:** `terms.read`, `terms.install`, `terms.activate`, `terms.license`, `terms.valueset.write`, `terms.export`, `terms.audit.read`. Alternatively, a roles claim that config maps to them.
5. **Identity claims for audit:** a stable `sub`, `client_id`/`azp`, and ideally `name` or `preferred_username`, so audit rows are readable without calling the IdP.
6. **Grants:** client credentials (services, CI) and device authorization (RFC 8628) for `ctl`. If device authorization isn't offered, `ctl` uses authorization code + PKCE on a loopback redirect.

---

## 4. Milestones

Each ends in something runnable. **Done when** is the definition of done.

### M0: Green build & hygiene (½–1 day)
- [ ] R1, R2, R3, R4, R6
- [ ] Root `CLAUDE.md` (provided)
- [ ] CI (`make ci` or GitHub Actions): `go build ./...`, `go vet ./...`, `staticcheck`, `buf lint`, `buf breaking` (once `api/` is on main)

**Done when:** `go build ./... && go vet ./...` pass; `go run ./cmd/ctl terms --help` lists 8 verbs; `buf lint` clean.

### M1: Terminology schema becomes a tested foundation (3–5 days)
- [ ] Fixes T1 (comment), T2, T3, T4, T5, T6, T7, plus C6 `effective_time` and C12 panel rekey. One commit per ID.
- [ ] Audit schema (D13): `terms_audit_event`; capture triggers on `code_system_version`, `code_system_enablement`, `value_set` and `terms_job`; a `SECURITY DEFINER` writer; an update/delete guard; grants. `activate_version()`/`rollback_version()` read the actor from `terms.actor`. These are new migrations if `001`–`015` have been applied anywhere you care about; otherwise edit in place.
- [ ] `internal/platform/db/migratetest`: testcontainers-go (`postgres:18`) + tern's `migrate` library. Applies `migrations/terminology` up → down to 0 → up.
- [ ] Port `docs/plan-evidence/behavior.sql` to Go tests: activation; rollback incl. the DOS case (T3); date-of-service resolution across Oct 1 and Apr 1; the validity trigger; the partition load recipe incl. the per-partition `module_id` FK; retire (T1); the delete guard (T2); enablement (T7).
- [ ] Audit tests: an activation with `terms.actor` set records the actor, before/after status and a DB-clock timestamp; a change made with no `terms.actor` (simulated `psql`) is recorded with `source = 'db'` and the DB role; `UPDATE`/`DELETE`/`TRUNCATE` on `terms_audit_event` fail for the app and import roles.
- [ ] `internal/terms/store/sqlc.yaml` (schema = `migrations/terminology`) with one smoke query.

**Done when:** `go test ./internal/platform/db/... ./internal/terms/store/...` passes on PG 18, including "May 2027 resolves to FY2027 after rolling back the April update" and the audit tests; `sqlc generate` succeeds.

### M2: Service skeleton (3–4 days)
- [ ] ADR-0001 server stack: grpc-go vs Connect (ROADMAP D1). `internal/platform/grpc` is empty, so it's a free choice. Connect is recommended, because one `net/http` mux then serves gRPC, gRPC-Web, JSON and later `/fhir`.
- [ ] `internal/platform/{cfg,db,grpc,telemetry}`, only what `cmd/terms` needs: TOML+env config, pgx pool (role, `search_path`, health), server bootstrap (recovery, logging, request id, health, reflection), slog + OpenTelemetry.
- [ ] `internal/terms/authn` (D10): load issuer metadata; validate JWT access tokens against JWKS (key rotation via `kid` refresh, clock-skew allowance, `aud` check) or introspect opaque tokens (cached ≤ 60 s, never past `exp`); produce a `Principal` (issuer, sub, client_id, display, scopes).
- [ ] `internal/terms/authz`: per-RPC scope table loaded from config; unknown RPCs fail closed; denied admin attempts are written to `terms_audit_event` with `outcome = 'denied'`.
- [ ] `internal/terms/audit`: `Begin(ctx, tx)` sets `terms.actor` / `terms.request_id` / `terms.reason` with `SET LOCAL` (via `set_config(..., true)`).
- [ ] `internal/terms/authn/fakeissuer`: an in-process OIDC issuer for tests (discovery, JWKS, token minting, introspection).
- [ ] `ctl` auth: `ctl login` (device authorization grant, PKCE fallback) with a token cache (0600) and refresh; `--client-credentials` mode for automation.
- [ ] `buf generate` → `api/gen/go`; every RPC returns `Unimplemented`.
- [ ] `cmd/ctl terms *` dial AdminService (address + credentials from config/flags); each verb currently prints "not implemented" with the RPC it will call.

**Done when:** `cmd/terms` starts against the M1 schema; against the fake issuer, no token → `Unauthenticated`; a wrong audience or expired token → `Unauthenticated`; a valid token without the required scope → `PermissionDenied` plus a `denied` audit row; a valid token with the scope reaches `Unimplemented`; a test asserts every registered RPC has a scope entry.

### M3: Loader framework + SNOMED (ROADMAP Phase 1, ~1–1.5 weeks)
- [ ] Job table + `SKIP LOCKED` worker; `StartIngest`/`StartInstall`/`GetJob`/`WatchJob`
- [ ] Generic partition installer (create `LIKE` → CHECK → `COPY` → PK/indexes → `ANALYZE` → FKs → `ATTACH` in dependency order) and retirer (T1 order), with cleanup on failure
- [ ] SNOMED RF2 snapshot loader with International + US layering, the closure build, derived `fsn`/`semantic_tag`/`preferred_term_en_us`
- [ ] `ValidateVersion` checks, including that the `module_id` FK exists on each partition
- [ ] `tools/terms-fixturegen` + `testdata/terms/rf2-mini/` (synthetic, valid Verhoeff check digits)
- [ ] `ctl terms ingest | install | validate | clean` end to end

**Done when:** the ROADMAP Phase 1 criteria pass: golden counts and closure on the fixture; reinstalling leaves the old version untouched; `clean` leaves no partitions or rows; a real US Edition installs and validates (timing recorded).

### M4: Activation, resolution, SNOMED reads, promotion (ROADMAP Phase 2, ~1 week)
- [ ] `ActivateVersion` / `RollbackVersion` over the M1 functions, audited with the caller's identity; `ctl terms activate | rollback`
- [ ] `ListAuditEvents` + `ctl terms audit` (filter by actor, action, target, time range)
- [ ] `internal/terms/resolve`: explicit pin → date of service → active; cache invalidated by `NOTIFY` on activation
- [ ] SNOMED read RPCs (`GetConcept`, `BatchGetConcepts`, `Traverse`, `ListRelationships`, `ListRefsetMembers`, `GetHistoricalAssociations`) and SNOMED via `TerminologyService` (`Lookup`, `BatchLookup`, `Subsumes`, `ValidateCode`, `ListCodeSystems`)
- [ ] `DiffVersions` (staged vs active), `ctl terms impact`
- [ ] **`ctl terms package`**: export a validated version as a signed artifact (source archives + `source_sha256` + validation counts/checksums). `ctl terms ingest --from-package` installs it in another terminology environment and verifies the checksums match.

**Done when:** ROADMAP Phase 2 criteria; activate → rollback → activate gives the expected answers with no restart, and `ctl terms audit` shows three events naming the user, with before/after status and timestamps; an install started by user A and finished by the worker is attributed to A; a package exported from one scratch instance installs into another with identical counts and checksums.

### M5: Search (ROADMAP Phase 3, ~1 week)
Typeahead over SNOMED, then over the generic provider. Relevance suite ≥ 90% top-3, p95 < 50 ms.

### M6: Other code systems (ROADMAP Phase 5, by tier, several weeks)
Generic table-driven provider first (covers most Tier 3), then the Tier 1 loaders (LOINC, RxNorm, ICD-10-CM/PCS, CPT, HCPCS, CVX, MVX, UCUM, NUCC, CDC race/ethnicity), resolving C7–C11 and the `TODO(verify)` notes as each system lands. Tier 2 follows.

### M7: ECL (ROADMAP Phase 4)
4a–4e staged, with the in-memory executor decision gate.
*Ordered after M6 deliberately: Tier 1 code systems unblock more CommonPoint workflows than refinement-level ECL does. Swap M6 and M7 if value-set authoring is needed sooner.*

### M8: Value sets → concept maps → FHIR facade (ROADMAP Phases 6–8)

### Deferred
ROADMAP Phase 9 hardening: generated clients, load tests, Kubernetes.

---

## 5. Risks

| Risk | Mitigation |
|---|---|
| Partition DDL edge cases (attach/detach order, FK cloning) | The loader is the only code path; M1/M3 tests cover install and retire for every partitioned family, not only SNOMED. |
| Licensed content leaks into the repo or fixtures | Synthetic fixtures only; `.gitignore`; a CI grep for RF2/RRF file headers. |
| Real-release surprises (`TODO(verify)` items) | Each loader's milestone includes a real-release install before its criteria are met. |
| IdP not ready when M2 starts | Everything is built and tested against the in-process fake issuer. Pointing `cmd/terms` at the real IdP is a config change once it meets the §3 contract. |
| IdP outage blocks terminology reads | JWT validation needs only cached JWKS (keep serving through brief IdP outages; refresh in the background). Introspection mode can't do this, which is another reason to prefer JWT access tokens. |
| Audit gaps from changes made outside the API | Triggers capture DB-level changes too (`source = 'db'`). Restrict direct DB access to the migrations role, and review `source = 'db'` events. |
