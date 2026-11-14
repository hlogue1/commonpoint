-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T8 / review C6: SNOMED components carry the RF2 effectiveTime of the row that was loaded
-- (with layered editions, the latest across packages). ECL effectiveTime filters, release
-- diffs and GetConcept.effective_time need it. Derived tables (snomed_closure) and the CORE
-- problem list subset (not an RF2 component) don't get it.
--
-- NOT NULL without a default: this applies to parents with no loaded partitions. A partition
-- loaded before this migration has no effective times to give and must be reinstalled.

ALTER TABLE snomed_concept ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_description ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_relationship ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_relationship_concrete ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_language_member ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_refset_member ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_history ADD COLUMN effective_time date NOT NULL;
ALTER TABLE snomed_extended_map ADD COLUMN effective_time date NOT NULL;


---- create above / drop below ----


ALTER TABLE snomed_extended_map DROP COLUMN effective_time;
ALTER TABLE snomed_history DROP COLUMN effective_time;
ALTER TABLE snomed_refset_member DROP COLUMN effective_time;
ALTER TABLE snomed_language_member DROP COLUMN effective_time;
ALTER TABLE snomed_relationship_concrete DROP COLUMN effective_time;
ALTER TABLE snomed_relationship DROP COLUMN effective_time;
ALTER TABLE snomed_description DROP COLUMN effective_time;
ALTER TABLE snomed_concept DROP COLUMN effective_time;
