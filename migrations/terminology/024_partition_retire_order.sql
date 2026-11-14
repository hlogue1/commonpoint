-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T1: the retire recipe in 002_snomed.sql ("DETACH + DROP, in the reverse order", read as
-- detach everything, then drop) fails: a detached partition keeps its FK, now pointing at the
-- parent, so the next DETACH is rejected. The correct order is per table, in reverse dependency
-- order, DETACH then DROP immediately. 002 is applied and can't be edited, so the recipe lives
-- in docs/terms/partition-lifecycle.md and this comment points there from the catalog.

COMMENT ON TABLE snomed_release IS
    'One row per installed SNOMED version. Partition install/retire order: docs/terms/partition-lifecycle.md (retire per table: DETACH then DROP immediately, reverse dependency order).';


---- create above / drop below ----


COMMENT ON TABLE snomed_release IS NULL;
