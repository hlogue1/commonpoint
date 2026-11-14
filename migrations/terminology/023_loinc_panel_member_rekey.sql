-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T8 / review C12: the TODO(verify) in 003_loinc.sql. PanelsAndForms.csv may repeat
-- (ParentLoinc, SEQUENCE) when a sub-panel is shared between top-level panels, which the old
-- PK (version_id, panel_loinc_num, sequence) would reject. Key on the file's own row id instead:
--   row_id               the file's ID column
--   parent_row_id        the file's PARENT_ID (the row of the enclosing panel), NULL at top level
--   top_panel_loinc_num  the top-level panel the row belongs to
-- parent_row_id has no self-FK: a parent-level self-FK on a partitioned table breaks DETACH
-- (see snomed_concept.module_id in 002_snomed.sql); the loader checks it instead.
-- Applies to a parent with no loaded partitions (NOT NULL without a default).

ALTER TABLE loinc_panel_member DROP CONSTRAINT loinc_panel_member_pkey;

ALTER TABLE loinc_panel_member
    ADD COLUMN row_id integer NOT NULL,
    ADD COLUMN parent_row_id integer,
    ADD COLUMN top_panel_loinc_num TEXT NOT NULL,
    ADD PRIMARY KEY (version_id, row_id),
    ADD CONSTRAINT loinc_panel_member_top_panel_fk
        FOREIGN KEY (version_id, top_panel_loinc_num) REFERENCES loinc_term (version_id, loinc_num) ON DELETE CASCADE;

CREATE INDEX loinc_panel_member_panel ON loinc_panel_member (version_id, panel_loinc_num, sequence);
CREATE INDEX loinc_panel_member_top_panel ON loinc_panel_member (version_id, top_panel_loinc_num);


---- create above / drop below ----


DROP INDEX loinc_panel_member_top_panel;
DROP INDEX loinc_panel_member_panel;
ALTER TABLE loinc_panel_member
    DROP CONSTRAINT loinc_panel_member_top_panel_fk,
    DROP CONSTRAINT loinc_panel_member_pkey,
    DROP COLUMN top_panel_loinc_num,
    DROP COLUMN parent_row_id,
    DROP COLUMN row_id,
    ADD PRIMARY KEY (version_id, panel_loinc_num, sequence);
