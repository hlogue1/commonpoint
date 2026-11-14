# CommonPoint Terminology Service: architecture & roadmap

Status: draft v0.3 (2026-11-13). Reconciled with the existing DDL, the monorepo layout, and the one-active-version-per-instance decision.
Owner: Harley · Working rules for Claude Code: `CLAUDE.md` · Schema fixes: `docs/terms/schema-review.md`

---

## 1. What this is

A standalone, read-mostly terminology service (`../cmd/terms`). Its feature set is modeled on SNOMED International's
**Snowstorm**, with a **gRPC** API, **PostgreSQL** storage in the existing per-code-system schema, and a
**FHIR R4 terminology facade**. Each terminology instance holds **one active version per code system**.
A CommonPoint environment that needs different versions binds to a different **terminology environment**
(deployment config: an endpoint URL).

| | Snowstorm | CommonPoint `terms` |
|---|---|---|
| Primary API | REST + FHIR | gRPC (+ FHIR R4 REST facade) |
| Storage | Elasticsearch | PostgreSQL 18, ~45 code systems in native table sets, big ones partitioned by `version_id` |
| Versioning | Branches (for authoring) | Immutable `code_system_version`s, one active per system per instance, plus **date-of-service** selection for billing code sets |
| SNOMED authoring | Yes | No, permanently out of scope |
| ECL | Full 2.x | Staged to full 2.x |

### Why it's practical
- The typed contracts pay off. The callers are the GTK/Rust client, Flex (Swift), Angular admin apps and the Go monolith, all generated from one set of protos.
- Streaming is a real benefit for large expansions, ECL results, bulk validation in migrations and interfaces, and install progress.
- FHIR stays the interop contract. RPCs mirror `$lookup`, `$validate-code`, `$subsumes`, `$expand` and `$translate` 1:1, so the facade is a translation layer.
- Postgres is enough for consuming one or two SNOMED editions: closure tables plus trigram and full-text search.
- Dropping authoring removes branching, merging and classification.

### The hard parts (budget accordingly)
ECL refinements and filters · RF2 layering correctness · search relevance · SNOMED→ICD-10-CM map rules · licensing gates across ~45 systems.

---

## 2. Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | **Go**, in the existing module. Server stack: **first read `../internal/platform/grpc`**. If it's built on `google.golang.org/grpc`, use grpc-go for `terms` and add Connect only when a browser client needs it. If it's empty, use `connectrpc.com/connect` (gRPC + gRPC-Web + JSON from one `net/http` mux, which also hosts `/fhir`). | Matches the existing platform layer. Connect wins only if nothing exists yet. |
| D2 | `buf` for lint, breaking checks and codegen. Protos in `../api/proto`, Go output in `api/gen/go`. | One contract for every client. |
| D3 | Keep the existing **per-code-system table sets** (`migrations/terminology/02..14`). | Already decided. Each model stays native. |
| D4 | **Partition rule:** every table for SNOMED, RxNorm, LOINC and NCIt is `PARTITION BY LIST (version_id)` (review P1). Small systems stay unpartitioned and are retired by `DELETE … WHERE version_id`. | Retiring the big systems becomes DETACH + DROP instead of multi-million-row deletes. |
| D5 | **One active version per code system per terminology instance.** Different versions for different CommonPoint environments = different terminology environments. Promotion TST→PRD = reinstall the same source (same sha256) in PRD's instance. | Keeps the schema's single-active model and a simple mental model. |
| D6 | **Version resolution** per code system: `explicit` pin (must be ready) → for date-of-service (DOS) systems, the active/superseded version whose validity contains `date_of_service` → else the active version (review B2). Implemented once in `internal/terms/resolve`, cached and invalidated on activate/rollback via `LISTEN/NOTIFY`. | Every answer is reproducible and auditable. |
| D6a | **Cross-instance identity** is `(code_system_id, version, source_sha256)`. `version_id` never leaves the instance (expansion ids, cache keys, audit, diff reports). | Per-install `uuidv7()`s differ between TST-terms and PRD-terms. |
| D7 | DB roles `cp_terms_migrations` / `cp_terms_import` / `cp_terms_app`. The app role can't modify content. | Least privilege on the serving path. |
| D8 | **sqlc + pgx**, with the sqlc schema read from `../migrations/terminology` (tern format). No ORM. | Explicit SQL ownership. |
| D9 | ECL compiles to a set-algebra IR with pluggable executors: SQL first, an in-memory bitmap executor only if the Phase 4 gate triggers. | No speculative infrastructure. |
| D10 | **The service is an OAuth2 resource server for the CommonPoint clinical IdP**, which runs as an outside service. It talks to the IdP only through standards: issuer metadata (OIDC discovery / RFC 8414), **JWT access tokens validated against the issuer's JWKS** (RFC 9068: `iss`, `aud`, `exp`, `nbf`, signature), or **RFC 7662 introspection** if the IdP issues opaque tokens (mode set in config; introspection results cached ≤ 60 s and never past `exp`). Required audience is configurable (default `commonpoint-terms`). **Authorization by scope, per RPC**, from a config table: reads need `terms.read`; admin RPCs need `terms.install`, `terms.activate`, `terms.license`, `terms.valueset.write`, `terms.export` or `terms.audit.read`. An optional claim path lets roles from the IdP map to scopes. `ctl terms` gets tokens with the **device authorization grant** (RFC 8628) for people, falling back to authorization code + PKCE on a loopback redirect if the IdP lacks it, and **client credentials** for automation. Tokens are cached in the user config dir (0600). Services such as `../cmd/srv` use client credentials. Health checks are unauthenticated; reflection is dev-only. No IdP internals and no IdP code in this repo's terms packages. | Standards-only coupling keeps the IdP swappable and replaceable by any compliant issuer in tests. |
| D11 | **Generic table-driven provider** for simple code lists: a Go spec per system (table, code column, display column, active expression, optional parent column, search column). Only systems with real semantics get hand-written providers. | Makes ~30 of the 45 systems nearly free and replaces `concept_index` on the hot path. |
| D12 | **PostgreSQL 18 only. No Doltgres.** Releases are ingested from files on disk (`ingest` directory) and verified by SHA-256. Version history lives in `code_system_version` + `version_activation_log` + `terms_audit_event`. Plain containers (Podman) until Phase 9. | One database technology to operate. Provenance comes from checksums and the audit trail. |
| D13 | **Audit trail = `terms_audit_event`, append-only, written by database triggers.** Within each mutating request the API sets transaction-local `terms.actor` (issuer, subject, client_id, display, scopes), `terms.request_id` and `terms.reason`. Triggers on the control tables (`code_system_version`, `code_system_enablement`, `value_set`, `terms_job`) record action, target (natural ids per D6a), before/after row JSON, and the time from `clock_timestamp()`. Changes made outside the API (e.g. `psql`) are still captured, with `source = 'db'` and the DB role as the actor. Async jobs store the starting principal, and the worker sets `terms.actor` from it, so an install is attributed to whoever started it. Denied admin attempts are written by the authz interceptor (`outcome = 'denied'`). The table is insert-only: the trigger function is `SECURITY DEFINER`, all other roles get no UPDATE/DELETE/TRUNCATE, and a guard trigger rejects updates and deletes. Content rows (millions per release) aren't row-audited; the version is the unit of change, and its `source_sha256` + validation checksums prove its content. Queried via `AdminService.ListAuditEvents` / `ctl terms audit`. | Answers "who changed what, when" for every change path, including ones that bypass the service. |

---

## 3. Architecture

```
 GTK (tonic) ─┐                      cmd/terms
 Flex (swift) ┤   ┌─────────────────────────────────────────────────────┐
 Angular ─────┼──▶│ gRPC handlers: TerminologyService, SnomedService,   │
 cmd/srv ─────┤   │                AdminService                         │
 cmd/ctl ─────┘   │ FHIR R4 facade /fhir/...                            │
 External/SMART ─▶│        │                                            │
                  │  interceptors: OAuth2 (JWT/introspect) → scope authz│
                  │                → audit ctx → resolve(Context)       │
                  │        │                                            │
                  │  ┌─────┴──────┬──────────────┬───────────┐          │
                  │  │ providers  │ ecl          │ valueset  │          │
                  │  │ snomed,    │ parser→IR→   │ conceptmap│          │
                  │  │ loinc, rx, │ sql executor │ search    │          │
                  │  │ icd10cm,.. │              │           │          │
                  │  │ generic(*) │              │           │          │
                  │  └─────┬──────┴──────────────┴───────────┘          │
                  │  loader: ingest/install/validate/retire jobs        │
                  └────────┬────────────────────────────────────────────┘
                           │ pgx (search_path = terms)
                  ┌────────▼────────┐        ┌────────────────────┐
                  │ terms DB (PG 18)│        │ CommonPoint        │
                  │ incl. append-   │        │ clinical IdP       │
                  │ only audit trail│        │ (external, OAuth2) │
                  └─────────────────┘        └────────────────────┘
                           ▲ JWKS / introspection: cmd/terms ─────────▶ IdP
```

### Provider interface (sketch)
```go
type Provider interface {
    CodeSystemID() string            // code_system.id, e.g. "icd10cm"
    URI() string                     // canonical, from code_system.uri
    Lookup(ctx context.Context, v VersionID, code string, o LookupOpts) (*Concept, error)
    Validate(ctx context.Context, v VersionID, code, display string, dos *civil.Date) (*Validation, error)
    Subsumes(ctx context.Context, v VersionID, a, b string) (Subsumption, error) // ErrUnsupported for flat systems
    Search(ctx context.Context, v VersionID, q SearchQuery) (SearchPage, error)
    Filter(ctx context.Context, v VersionID, f []ValueSetFilter) (CodeSet, error)
}
```

### Code system tiers (drives Phase 5 ordering)
- **Tier 1, needed for an EHR MVP:** snomed, loinc, rxnorm, icd10cm, icd10pcs, cpt, hcpcs, cvx, mvx, ucum, nucc, cdc_race_ethnicity
- **Tier 2, meds knowledge and revenue cycle:** medrt, atc, uspmg, cms_frf, ncci, cdt, sop, abc, icd9cm (+ GEMs), ccsr_dx, ccsr_pr, ccs
- **Tier 3, specialty, mostly through the generic provider:** nanda, nic, noc, omaha, pnds, icpc2, icpc2plus, icpc2_icd10, icf, hgnc, hpo, mondo, orphanet, ncit, pdq, meddra, umdns, chv, medlineplus, umls

---

## 4. Roadmap

Each phase ends in something runnable. **Done when** is the definition of done.

### Phase 0: Skeleton + schema fixes
- [ ] Verify how tern sees `../migrations/terminology` (`tern status`). Rename to `NNN_name.sql` if needed (B3). Add `deploy/db/tern-terms.conf` (DB `commonpoint_terms`, version table `terms.schema_version`, `search_path=terms`).
- [ ] Apply the schema review in this order, one commit per ID: **B2, B4, C5, C1, C2, C3, P1, P5**, then C6, C7, C8, C12, P2, plus the B5 identity items (`UNIQUE (code_system_id, version)`, `source_sha256`, `activated_at`, `validated_at`). (B1 is done; C4, C9–C11, C13, C14 are tracked as Phase 5 tasks.)
- [ ] New migration for job tables: `terms_job(id uuid, kind, state, version_id, phase, progress, issues jsonb, started_by, …)` with a `SKIP LOCKED` queue; `version_activation_log` (who/when/reason for every activate and rollback); plus `value_set(url, version, status, definition jsonb)` and `expansion_cache`.
- [ ] Roles and grants (D7) in a migration, parameterized via tern data variables.
- [ ] `../buf.yaml` / `buf.gen.yaml` at the root; generate into `api/gen/go`; pick the server stack per D1 and record it in `docs/terms/adr/0001-server-stack.md`.
- [ ] `../cmd/terms`: server with health, reflection, slog, telemetry; all RPCs return `Unimplemented`.
- [ ] `internal/terms/store`: sqlc config, pool with `search_path`, and a testcontainers helper (postgres:18) that runs the tern migrations.
- [ ] `cmd/ctl/cli/terms/*`: wire each existing verb to its AdminService RPC (mapping in `admin_service.proto` header comment). Each command can return "not implemented" for now.
- [ ] CI: `buf lint`, `buf breaking`, `go vet`, `staticcheck`, `go test -race ./internal/terms/... ./cmd/ctl/...`
- [ ] `../.gitignore`: `/data/`, `*.zip`, `*.RRF`, `*.rrf`

**Done when:** migrations apply cleanly to an empty PG 18 from scratch *and* down/up round-trips; `grpcurl … list` shows 3 services; constraint tests pass: a second SNOMED version can be staged and activated (the old one becomes superseded), an unloaded version can't be activated, two ICD-10-CM versions with overlapping validity can't both be active/superseded, and `resolve_version('icd10cm', date)` picks the right fiscal year on either side of October 1.

### Phase 1: Ingest/install framework + SNOMED RF2
- [ ] Loader framework: `Ingest` (verify SHA-256, register `code_system_version` as `staged`/`loading`) → `Install` (create partitions `LIKE … INCLUDING …`, `CHECK (version_id = …)`, `COPY`, PK/indexes, `ANALYZE`, FKs incl. the per-partition `module_id` FK, `ATTACH` in dependency order) → `load_status = ready`. Run as `cp_terms_import`. Make it idempotent, with cleanup on failure (drop unattached partitions).
- [ ] `Retire`: the reverse order, with DETACH + DROP. Refuse the active version, and refuse a superseded DOS version whose validity still covers dates within the configured claims look-back window.
- [ ] SNOMED RF2 Snapshot reader: concepts, descriptions + text definitions, inferred relationships, concrete relationships, language refsets, simple refsets, association refsets → `snomed_history`, extended map → `snomed_extended_map`, CORE problem list subset.
- [ ] Edition layering (International + US into one version_id), choosing the latest effectiveTime per component id.
- [ ] Derive `fsn`, `semantic_tag`, `preferred_term_en_us`, `fully_defined`.
- [ ] Build `snomed_closure` from active inferred is-a, with `depth` = shortest path. Benchmark Go BFS + `COPY` against a recursive CTE, keep the faster, and record the result.
- [ ] `ValidateVersion` checks: every active concept has an FSN and an en-US PT; the closure is acyclic; every active non-root concept has ≥1 parent; relationship endpoints exist; the module FK is present on every partition.
- [ ] `tools/terms-fixturegen` + `testdata/terms/rf2-mini/`: ~50 invented concepts with valid Verhoeff check digits, covering multiple inheritance, an inactive concept with REPLACED BY, attribute groups, a concrete value, and both en-US and en-GB.
- [ ] `ctl terms ingest|install|validate|clean` work end to end for SNOMED.

**Done when:** the fixture installs with golden counts and closure; reinstalling the same source creates a new version and leaves the old one untouched; `clean` fully removes a version (no orphan partitions or rows); a real US Edition install passes validation (timing in `docs/terms/benchmarks.md`).

### Phase 2: Activation, resolution, SNOMED reads
- [ ] `ActivateVersion`, `RollbackVersion`, `ListVersions` over `activate_version()` / `rollback_version()` (review B4), each logged to `version_activation_log` and audited. Wire `ctl terms activate|rollback`.
- [ ] `internal/terms/resolve` per D6, with cache invalidation on `NOTIFY terms_version_changed`.
- [ ] `SnomedService`: `GetConcept`, `BatchGetConcepts`, `Traverse` (4 directions, paged), `ListRelationships`, `ListRefsetMembers`, `GetHistoricalAssociations`.
- [ ] `TerminologyService` for SNOMED: `Lookup`, `BatchLookup`, `Subsumes`, `ValidateCode` (no value set yet), `ListCodeSystems`.
- [ ] Signed, opaque page tokens that embed `version_id` and are rejected if the resolved version differs.
- [ ] OAuth2 resource-server auth + per-RPC scopes (D10), tested against an in-process fake issuer (JWKS + introspection endpoints). The audit trail (D13) captures every activate/rollback/enablement change with the token's subject. `ctl terms audit` lists events.

**Done when:** fixture golden tests pass for every RPC; activate → rollback → activate gives the expected answers at each step, and no restart is needed (cache invalidation works); on the real US Edition, warm p95 `GetConcept` < 5 ms and `Traverse(CHILDREN)` < 10 ms.

### Phase 3: Search
- [ ] Add a `tsvector` (simple + unaccent) on `snomed_description` alongside the existing trigram index. Word-prefix any-order matching (`hear att` → `hear:* & att:*`), with trigram fallback when there are zero hits.
- [ ] Ranking: exact PT > PT word-prefix > synonym > FSN, shorter first, active first. Deterministic tie-break on code.
- [ ] Filters: semantic tag, active, module. An ECL pre-filter that accepts only `<< id` until Phase 4. One hit per concept, with `matched_term`.
- [ ] Generic search over `search_column` for every generic-provider system. Cross-system search via `systems[]`.
- [ ] `testdata/terms/search-cases.yaml`: ~50 queries → expected top-3 (IDs and query strings only).

**Done when:** ≥ 90% top-3 on the real edition; p95 < 50 ms for 1–3 tokens.

### Phase 4: ECL
- [ ] Vendor the official ANTLR4 ECL grammar (pin the commit, record it in `docs/terms/ecl.md`) and generate Go with `antlr4-go`.
- [ ] AST → IR → simplifier → SQL executor over `snomed_closure`, `snomed_relationship`, `snomed_relationship_concrete` and `snomed_refset_member`.
- [ ] `ParseEcl` with error positions and normalized brief syntax.
- [ ] Stages, each with YAML cases in `testdata/terms/ecl/`:
  - [ ] 4a: `< << > >> <! >! <<! >>!`, `^`, `*`, AND/OR/MINUS, nesting
  - [ ] 4b: refinements (attributes, groups, cardinality, reverse, concrete values)
  - [ ] 4c: dot notation, top/bottom
  - [ ] 4d: description, concept and member filters (needs C6 `effective_time`)
  - [ ] 4e: history supplements (`snomed_history`)
- [ ] `EvaluateEcl`, `StreamEvaluateEcl`, ECL in Search, timeouts and result caps.

**Done when:** all spec examples that can be evaluated on the fixture pass; `<< 404684003` streams fully in < 3 s on the real edition. **Gate:** if refinement-heavy queries are > 1 s p95, write an ADR for the in-memory executor.

### Phase 5: Other code systems (by tier)
- [ ] Generic provider (D11) with a spec registry. Port every row of `concept_index` into specs. Hierarchy via recursive CTE on `parent_code` where present (P3).
- [ ] **Tier 1** loaders + providers:
  - LOINC (C11 hierarchy decision first; answer lists; panels per C12)
  - RxNorm (C7 `rxnorm_term`; PSN display; NDC; history; `prescribable`)
  - ICD-10-CM (C10 sections; notes; 7th characters; DOS validity)
  - ICD-10-PCS
  - CPT (license gate; C8)
  - HCPCS (C9 D-code handling; per-DOS activity per C1)
  - CVX, MVX, UCUM, NUCC, CDC race/ethnicity
- [ ] License gate (CLAUDE rule 11); fix tiers per C4; verify URIs per C14.
- [ ] **Tier 2:** MED-RT (resolve its TODO), ATC + DDD, USP MMG, CMS FRF, NCCI, CDT, SOP, ABC, ICD-9-CM + GEMs, CCSR, CCS (per C3).
- [ ] **Tier 3:** through the generic provider, plus hand-written closure for HPO and NCIt (already modeled). Mondo gets a closure only if benchmarks need it.
- [ ] Synthetic fixture per loader in its native format.

**Done when:** for every Tier 1 system, `Lookup`/`ValidateCode`/`Search` (+ `Subsumes` where hierarchical) pass fixture tests, and real-release installs succeed. ICD-10-CM `ValidateCode` honors `date_of_service` across an October→April boundary.

### Phase 6: Value sets
- [ ] `PutValueSet`, `PublishValueSet`, `GetValueSet`, `ListValueSets`
- [ ] Expansion: includes/excludes, codes, filters (`is-a`, `descendent-of`, `=`, `in`, `regex`, `constraint`=ECL), nested value sets with cycle detection; implicit SNOMED value sets (`fhir_vs=ecl/…|isa/…|refset/…`)
- [ ] Paged and streamed `ExpandValueSet` with `filter`; `ValidateCode` against a value set via IR membership, without a full expansion where possible
- [ ] Expansion cache keyed by `hash(definition, resolved (code_system_id, version, source_sha256))` (D6a), so expansion ids match across terminology environments
- [ ] `DiffVersions` (default: staged vs active) with value set impact; wire `ctl terms impact`

**Done when:** golden expansions pass; the fixture diff reports an inactivation with its REPLACED BY target and the resulting value-set membership change.

### Phase 7: Concept maps
- [ ] SNOMED extended map → `Translate` with group/priority/rule/advice and a **rule evaluator** (`IFA`, age/sex predicates, `OTHERWISE TRUE`) driven by `map_context`
- [ ] Other existing maps exposed as ConceptMaps: ICD-9↔ICD-10 GEMs, ATC↔RxNorm, MED-RT↔RxNorm, LOINC MAP_TO, HPO/Mondo/Orphanet xrefs, ICPC-2→ICD-10 (WHO)
- [ ] Stored local FHIR ConceptMaps

**Done when:** a fixture map with rules translates correctly over an age/sex matrix.

### Phase 8: FHIR R4 facade
- [ ] `/fhir/metadata` (+ `?mode=terminology`); `CodeSystem/$lookup|$validate-code|$subsumes`; `ValueSet/$expand|$validate-code`; `ConceptMap/$translate`; read/search of CodeSystem/ValueSet/ConceptMap metadata
- [ ] `Parameters` in and out, `OperationOutcome` for errors, JSON first; `system-version` / `force-system-version` mapped to TerminologyContext
- [ ] Run the HL7 terminology ecosystem tests that apply; record the pass rate

**Done when:** every operation is exercised by a Postman/HAPI CLI collection; ecosystem tests pass, or each failure is documented with a reason.

### Phase 9: Hardening & clients
- [ ] Generated clients: Rust (GTK / `commonpoint-core`), Swift (Flex), TS (Angular)
- [ ] Load tests (ghz), pool tuning, read-replica notes; the optional in-memory ECL executor if gated
- [ ] OWL axioms → stated view; MRCM refsets (C13) → ECL attribute validation
- [ ] Container image, then Kubernetes manifests last

---

## 5. Performance targets (initial, warm, single node)

| Operation | p95 |
|---|---|
| Lookup / GetConcept | < 5 ms |
| BatchLookup (100) | < 25 ms |
| Search | < 50 ms |
| ValidateCode against a cached value set | < 5 ms |
| EvaluateEcl, simple, first page | < 100 ms |
| US Edition install | measure; target < 30 min |

## 6. API conventions
- Package `commonpoint.terminology.v1`; breaking changes go in `v2`, enforced by `buf breaking`.
- Code systems are identified by canonical URI in the generic API and by `code_system_id` in AdminService.
- Every read accepts a `TerminologyContext`; expansions echo the versions used.
- Paging: `page_size` (default 50, max 1000) + opaque `page_token`.
- Errors: gRPC status + `google.rpc.ErrorInfo` (`domain = "terms.commonpoint"`, reasons like `CODE_SYSTEM_DISABLED`, `VERSION_NOT_READY`, `ECL_SYNTAX`). Domain failures come back as `Issue`s.
- Metadata: `traceparent`. Callers don't pass an environment: the instance *is* the environment.

## 7. Open questions
1. ~~What is `ctl terms package` for?~~ Resolved: "Export terminology artifact", i.e. a signed promotion bundle (`AdminService.ExportPackage`).
2. Value sets live in `terms` (Phase 6). They're per terminology environment, so `ctl terms package` should be able to export them for promotion too.
3. A local SNOMED extension namespace for CommonPoint-local concepts? Defer.
4. Offline terminology for downtime/BCA devices: a SQLite export of the active versions? It would affect the D9 gate timing.
5. Should license tier be a property of the version/edition (US SNOMED via UMLS vs affiliate) rather than the code system? (Review C4.)
6. Claims look-back window for retiring superseded DOS versions (Phase 1 `Retire`): is a configurable number of years per code system enough?

## 8. Licensing guardrails
- **No terminology content in the repo, ever.** Fixtures are synthetic; real releases live under `/data/`, git-ignored.
- `code_system_enablement` + `license_reference` gate installation for every tier except `open`.
- `ListCodeSystems` and `/fhir/metadata` show publisher, copyright and license tier for each enabled system.
