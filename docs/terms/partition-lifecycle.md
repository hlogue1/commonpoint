# Partition lifecycle for versioned content tables

<!-- SPDX-License-Identifier: GPL-3.0-or-later -->

This supersedes the retire recipe in the header of `migrations/terminology/002_snomed.sql`
(finding T1). Applied migrations aren't edited, so the corrected recipe lives here and
`024_partition_retire_order.sql` points to it. The loader (`internal/terms/loader`, M3) is the only
code that runs these steps, as `cp_terms_import`, which owns every partitioned table.

## Install (unchanged)

For each table of the family, in dependency order (referenced tables first):

```sql
CREATE TABLE <t>_<release> (LIKE <t> INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED);
ALTER TABLE <t>_<release> ADD CHECK (version_id = '<version uuid>');
COPY <t>_<release> FROM ...;
-- primary key and the parent's indexes
ANALYZE <t>_<release>;
ALTER TABLE <t> ATTACH PARTITION <t>_<release> FOR VALUES IN ('<version uuid>');
```

`snomed_concept` also needs its per-partition `module_id` FK before ATTACH (see `002_snomed.sql`).

SNOMED attach order: `snomed_concept`, then `snomed_description`, `snomed_relationship`,
`snomed_extended_map`, `snomed_core_problem_list`, then `snomed_language_member`; the rest in any
order. Other families: attach `rxnorm_concept`, `loinc_term` + `loinc_answer_list`,
`ncit_concept`, `hpo_term`, `mondo_term` first.

## Retire (corrected)

**Per table, in reverse dependency order: DETACH, then DROP that partition immediately, then
move on to the next table.**

```sql
ALTER TABLE snomed_language_member DETACH PARTITION snomed_language_member_<release>;
DROP TABLE snomed_language_member_<release>;
ALTER TABLE snomed_core_problem_list DETACH PARTITION snomed_core_problem_list_<release>;
DROP TABLE snomed_core_problem_list_<release>;
-- ... snomed_extended_map, snomed_relationship, snomed_description, the unordered tables ...
ALTER TABLE snomed_concept DETACH PARTITION snomed_concept_<release>;
DROP TABLE snomed_concept_<release>;
```

Then delete the version (`DELETE FROM code_system_version WHERE id = ...`), which cascades to
`<system>_release`. The T2 guard rejects that delete while any partition for the version exists.

Two orders that look reasonable fail:

- **Detach every partition first, drop afterwards.** A detached partition keeps its foreign keys,
  which now point at the *parent* table. Detaching the referenced partition next is rejected,
  because the detached table still has rows that reference it.
- **DROP an attached partition.** Dropping a partition that other partitions reference fails.

Unpartitioned small systems (CVX, SOP, NUCC, ...) are retired by deleting the version, which
cascades through `<system>_release`.

`internal/terms/store/retire_test.go` installs every SNOMED table and checks both the failing order
and the correct one.
