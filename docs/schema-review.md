# Terminology schema review — `migrations/terminology/01..15`

> **Status 2026-11-13 (repo `c18c8bf`):** most items here have since been applied in
> `../migrations/terminology/001_core.sql`–`015`: B1, B2, B3 (renamed `NNN_`), B4 (ready-check), C1 (release-relative
> HCPCS activity), C2, C3 (`ccs_ml`), C4 (tiers), P1 (all big families partitioned). B5 was withdrawn (one active
> version per instance). **Open items and newly verified bugs are tracked in `docs/PLAN.md` §2 (T1–T8)**, which
> supersedes this file for planning. It's kept for its rationale.


Reviewed: 2026-11-13, against the files as written before terminology moved into its own service.
Scope: correctness, fit with the separate-service design (`docs/ROADMAP.md`), and operations.

Severity: **B** = blocker (migration fails or behavior is wrong), **C** = correctness/design,
**P** = performance/operations. Every item has an ID so commits can reference it (`fix(terms-schema): B2`).

> If these migrations have **never been applied to a database you care about**, fix them in place
> and renumber (see B3). If they have, write forward migrations instead. Don't edit applied files.

---

## What's already good (keep it)

- The `(version_id, …)` composite key everywhere, with list partitioning on the big tables. This is the right shape for immutable, package-like releases.
- The per-partition `module_id` self-FK on `snomed_concept`, which avoids the DETACH problem, plus the documented load/retire order.
- `<system>_release` tables pinned with `CHECK (code_system = '…')` plus a composite FK into `code_system_version`. Nothing can attach to the wrong code system.
- Generated columns as FK targets (MedDRA `pt_level` / `hlt_level` …, ATC `level`, ICPC-2 component). Clever and cheap.
- Non-reflexive closure, with `snomed_subsumes()` handling `a = b`. Documented.
- The text-vs-citext parameter note in `15`. It's subtle, and you caught it.

---

## Blockers

### B1 — Missing extensions ✅ resolved
`pg_trgm` and `btree_gist` added; PostgreSQL 18 is the target (built-in `uuidv7()`).
Still worth adding `btree_gin` if you take P2. The `CREATE EXTENSION plpgsql` line is harmless but unnecessary.

### B2 — New versions default to `active`; validity overlap blocks staging and activation
Still applies under the one-active-version-per-instance model:
- `status DEFAULT 'active'` + `code_system_version_one_active`: inserting a second version of a system
  fails unless the loader overrides `status`, and a `loading`/`failed` row can be "active".
- `EXCLUDE … validity WITH &&` covers every non-retired row. A new SNOMED version can't be inserted
  while the active one's validity is open-ended, and on activation the superseded version (still
  non-retired) overlaps the new one, so `activate_version()` itself violates the constraint.

Fix: add a `staged` state, and give validity meaning only for date-of-service systems.
```sql
CREATE TYPE code_system_status AS ENUM ('staged', 'active', 'superseded', 'retired');
-- status DEFAULT 'staged'
-- validity daterange NULL        -- NULL = not date-of-service versioned (SNOMED, LOINC, RxNorm, ...)
CHECK (validity IS NULL OR NOT isempty(validity)),
EXCLUDE USING gist (lower(code_system_id::text) WITH =, validity WITH &&)
    WHERE (status IN ('active', 'superseded') AND validity IS NOT NULL)
```
Enforce `validity IS NOT NULL` iff `code_system.date_of_service_versioned` with a trigger (a CHECK
can't see the parent row).

Then update the resolver functions so non-DOS systems resolve to the active version regardless of date:
```sql
-- inside version_for_date (both overloads, or the single renamed one from C5)
WHERE ...
  AND v.load_status = 'ready'
  AND (   (v.validity IS NULL AND v.status = 'active')
       OR (v.validity @> p_date AND v.status IN ('active', 'superseded')))
```
For DOS systems this means FY2027 ICD-10-CM can be installed in August and activated before
October 1. Claims dated September still resolve to FY2026 (superseded), and claims dated October
resolve to FY2027.

### B3 — Migration filenames probably aren't picked up by tern
Files are named `01-core.sql`. As far as I know, tern only recognizes files whose names start with a sequence number **followed by an underscore** (`001_core.sql`, which is what `tern new` produces). **Verify with `tern status`** against a scratch DB before anything else. If it reports 0 migrations, rename `NNN-name.sql` → `NNN_name.sql`. The other migration directories may have the same problem.
Also:
- Give the terminology DB its own version table (`--version-table terms.schema_version`), so it never collides with the core/clinical/build migration sets.
- Add the `---- create above / drop below ----` marker with down SQL, or leave it out deliberately for irreversible files.
- `CREATE INDEX` on partitioned parents is fine inside tern's per-migration transaction. Only add `---- tern: disable-tx ----` for `CONCURRENTLY`.

### B4 — `activate_version()` can activate a version that isn't loaded, and has no rollback partner ✅ resolved
Ready-check (001), `code_system` row lock and `rollback_version()` (019, T3), `validated_at` required for activation (025).
- Add `IF (SELECT load_status FROM code_system_version WHERE id = p_version_id) <> 'ready' THEN RAISE …`.
  Also require a passing validation (add `validated_at timestamptz` to `code_system_version`, set by `ctl terms validate`).
- Lock the `code_system` row (`SELECT … FROM code_system WHERE id = … FOR UPDATE`) instead of only the
  target version. Two concurrent activations for the same system then serialize instead of one failing
  on the unique index.
- Add `rollback_version(p_code_system_id citext)`: re-activate the most recently superseded version
  (by `activated_at`, a new column) and move the current active one back to `staged`. `ctl terms rollback` calls it.

### B5 — ~~One global "active" version per database~~ Withdrawn
Decision: one active version per code system **per terminology instance**. A CommonPoint environment
that needs different versions depends on a different terminology environment (deployment config).
The single-active model stays. Two consequences carried into the design:
- **Cross-instance identity:** `version_id` is a per-install `uuidv7()`, so the same SNOMED release has
  different `version_id`s in TST-terms and PRD-terms. Anything that leaves the instance (expansion ids,
  cache keys, audit/provenance, diff reports, page tokens shown to other services) must identify a
  version by `(code_system_id, version, source_sha256)`, never by `version_id`. Consider
  `UNIQUE (code_system_id, version)` plus a stored `source_sha256` so the same release can't be
  installed twice under different contents.
- **Promotion** between terminology environments is done by a separate ETL (decided 2026-11-13; out of
  scope for the service, no packaged artifacts). The installer must still be deterministic, so the same
  release gives the same row counts and content checksum in every terminology environment.

---

## Correctness / design

### C1 — `concept_index` depends on `current_date`
The HCPCS branch computes `active` as `COALESCE(upper(validity) > current_date, true)`. The answer then changes from one day to the next with the same release, which breaks the reproducibility rule, and `validate_code(p_date)` ignores `p_date` for this flag. Compute HCPCS activity against the requested date of service, in the provider, not in the view.

### C2 — `date_of_service_versioned` is never set
Every `code_system` row gets the default `false`. Set it `true` at least for `icd10cm`, `icd10pcs`, `cpt`, `hcpcs`, `ncci`, `cdt`, and probably `icd9cm` for historical claims. Decide whether `cvx` and `sop` count.

### C3 — CCS codes collide in `concept_index`
The `ccs` branch emits `kind || ':' || code`, but the PK includes `scheme`. Single-level and multi-level CCS both use small integers at the top level (`dx:1` exists in both), so `lookup('ccs','dx:1')` returns two rows. Either make `ccs_single` and `ccs_multi` separate code systems (cleanest, since they really are different classifications), or include the scheme in the code.

### C4 — License tiers ✅ resolved
`rxnorm` and `snomed` are `umls` (001); `nanda_elsevier` split into `nanda_i` and `elsevier` (030). Per-edition tiers aren't needed while one instance serves one deployment.
- `rxnorm` is tagged `open`. As far as I know, the **full** RxNorm monthly release requires a UMLS license, and only the "Current Prescribable Content" subset doesn't. Tag it `umls`, or split prescribable into its own tier.
- `snomed` is tagged `snomed_affiliate`. A US deployment gets the US Edition through the UMLS license (the US is a SNOMED member country). Use `umls` for US deployments and keep `snomed_affiliate` for non-member use. Consider making the tier a property of the **version/edition**, not the code system.
- The `nanda_elsevier` tier name: NANDA-I and NIC/NOC have different publishers, so a combined tier makes per-publisher license tracking harder. Minor, but cheap to split now.

### C5 — The `version_for_date` overload footgun
The comment explains it, but an untyped literal silently picks the URI overload and returns NULL. That's a bug waiting for a future caller. Rename to `version_for_date_by_uri` / `version_for_date_by_id`, or fold both into one `resolve_version(code_system_id, date)` that implements the B2 logic.

### C6 — SNOMED tables don't store `effective_time`
ECL `effectiveTime` filters, release diffs ("what changed since our last upgrade"), and `GetConcept.effective_time` all need it. Add `effective_time date NOT NULL` to concept, description, relationship and refset members. The cost is small.

### C7 — RxNorm keeps one name per RXCUI
`rxnorm_concept(rxcui PK, tty, name)` keeps the concept-level atom and drops `PSN` (the prescribable name you want on order screens and in eRx), `TMSY` (tall-man) and `SY`. Add:
```sql
CREATE TABLE rxnorm_term (version_id uuid, rxcui text, tty text REFERENCES rxnorm_tty, name text,
                          PRIMARY KEY (version_id, rxcui, tty, name)) PARTITION BY LIST (version_id);
```

### C8 — CPT `category` enum ✅ resolved (026: `MAAA` value + category/code-shape CHECK)
The regex accepts the `M` suffix (Administrative MAAA codes), but `cpt_code_type` has no value for them. Add `'MAAA'`, or map M codes explicitly in the loader.

### C9 — HCPCS D-codes vs CDT ✅ resolved (027: `hcpcs_code` rejects `D%`; the loader skips them)
The CMS HCPCS Level II file includes `D` codes, which are ADA CDT content. Unless the `cdt` license is enabled, the HCPCS loader should skip `D%` codes, or store them without ADA descriptors, so CDT content can't arrive through the "open" HCPCS tier. Check the current CMS file's ADA notice.

### C10 — ICD-10-CM hierarchy stops at 3-character categories ✅ resolved (028: `icd10_chapter`, `icd10_section`, `icd10_code.section_id`)
The code regex can't hold chapter ranges or blocks (`E08-E13`), so `parent_code` is NULL for every category. Traverse/Subsumes can't answer "is E11.9 in E08-E13?", and pickers can't browse by block. Add `icd10_section(version_id, id text, chapter smallint, first_code, last_code, title)` and give categories a `section_id`.

### C11 — LOINC has no hierarchy ✅ resolved (029: `loinc_hierarchy` + `loinc_closure` + `loinc_subsumes()`, filled by the M6 loader)
Without the multiaxial hierarchy (LOINC's accessory files), `Subsumes`/`Traverse` for LOINC can't work, and neither can `is-a` filters in value sets (Phase 5). Add `loinc_hierarchy(version_id, path_to_root, sequence, immediate_parent, code, code_text)` plus a closure, or confirm you'll treat LOINC as flat at first.

### C12 — `loinc_panel_member` primary key
Do the rekey from your TODO now (`row_id` / `parent_row_id` / `top_panel_loinc_num`). It costs nothing on an empty schema and removes a load-time failure mode whatever the file turns out to contain.

### C13 — SNOMED gaps, for the backlog
- No attribute-value refsets, so no **inactivation reason** for `GetHistoricalAssociations`.
- `snomed_refset_member` has no member UUID and no extra columns, so it covers simple refsets only. That's fine for now; just document it.
- No MRCM refsets, which Phase 9 (ECL attribute validation) needs.

### C14 — URIs to verify
Check every non-`urn:commonpoint:cs:` URI against terminology.hl7.org (THO) once, and record the check date in a comment. In particular, double-check `mvx`, `cdt`, `hgnc`, `medrt`, `mondo` and `orphanet`. Some of the `urn:commonpoint:cs:` placeholders may have THO URIs now.

---

## Performance / operations

### P1 — Partition the big SNOMED child tables too
`snomed_language_member`, `snomed_refset_member`, `snomed_history`, `snomed_extended_map` and `snomed_relationship_concrete` aren't partitioned. For the US Edition, language members and refset members run to millions of rows per release, so retiring a release becomes a large `DELETE` plus vacuum instead of `DETACH` + `DROP`. FKs from a partitioned table to a partitioned table work fine. Partition them and keep the same attach order.
**Rule to put in CLAUDE.md:** every table for SNOMED, RxNorm, LOINC and NCIt is partitioned by `version_id`. Small systems (CVX, SOP, NUCC, …) stay unpartitioned and are retired by `DELETE … WHERE version_id = $1`.
The same applies to `ncit_parent` and `ncit_closure`: NCIt is large and deep, so its closure should be partitioned.

### P2 — Trigram indexes on unpartitioned, multi-version tables
On an unpartitioned table, `gin (long_desc gin_trgm_ops)` indexes every version together, so a search filtered to one version still walks the other versions' entries. With `btree_gin`, use `gin (version_id, long_desc gin_trgm_ops)`. Partitioned tables don't need this, because pruning already isolates the version.

### P3 — Hierarchy strategy per system
Closure tables exist for SNOMED, HPO and NCIt only. For the parent-pointer systems (ICD-10-CM, ATC, USP MMG, Mondo, Orphanet, MED-RT, Omaha, ICF, UMDNS, CDC race/ethnicity, SOP), use a generic recursive-CTE subsumption in the provider at first. Add closure tables only where benchmarks show a need. Mondo is the most likely candidate.

### P4 — `concept_index` off the hot path
A 45-branch `UNION ALL` view with function-parameter predicates works (each branch gets a cheap one-time filter), but the service no longer needs it. Each provider queries its own tables directly. Keep `concept_index` for ad-hoc SQL and reporting, and don't build RPCs on top of it.

### P5 — Schema qualification
The DDL is unqualified and depends on `search_path`. Since this is now its own database, create schema `terms`, set `search_path = terms` in the tern config and in the pgx pool's `AfterConnect`, and give the three roles (migrations / import / app) explicit grants on `terms`.
