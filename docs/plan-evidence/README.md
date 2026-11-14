# Plan evidence

How the findings in `docs/PLAN.md` §2 were verified (2026-11-13, repo at `c18c8bf`).

Environment: PostgreSQL **16.15** scratch server (18 wasn't installable in that environment), with a stand-in
`uuidv7()` (`gen_random_uuid()`) created before the migrations. Nothing else in the schema needs PG 18.

| File | What it shows |
|---|---|
| `runmig.sh` | Applies the "up" half (above the tern marker) of each `*.sql` in a directory, in order. |
| `01-apply-terminology.txt` | All 15 terminology migrations apply. (Down/up round-trip also verified, with 0 leftover tables, types or functions.) |
| `behavior.sql` / `02-behavior-terminology.txt` | Behavior tests (numbered `T1`–`T9` inside the script; mapping below). |

Behavior test → plan finding:

| behavior.sql | Result | Plan finding |
|---|---|---|
| T1 activate a loading version | ERROR, as intended | (guard works) |
| T2 two SNOMED versions via the partition recipe incl. module FK | works; undated resolves to active | (recipe works) |
| T3 rollback = `activate_version(previous)` | works for undated systems | (works) |
| T4 retire by detaching all, then dropping | **fails**: detached partition's FK blocks the next DETACH | **T1** |
| T4 (follow-up) `DELETE` of the version row | succeeds, but cascades and leaves empty partitions | **T2** |
| T5 validity trigger | both guards fire | (works) |
| T6 ICD-10-CM FY2026 / FY2027 / April update | correct date-of-service resolution | (works) |
| T7 re-activate FY2027 after the April update | May 2027 still resolves to `2027-04` | **T3** |
| T8 untyped literal | returns NULL | **T4** |
| T9 `lookup()` before an enablement row exists | 0 rows | **T7** |

Corrected retire order (verified): for `snomed_language_member`, `snomed_description`, `snomed_concept` in that
order, `ALTER TABLE <t> DETACH PARTITION <t>_<v>; DROP TABLE <t>_<v>;` one table at a time.

These scripts are seeds for the Go migration tests in milestone M1. Port them, then delete this folder.
