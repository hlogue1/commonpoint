-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C10: the ICD-10-CM hierarchy stopped at 3-character categories (parent_code is NULL for
-- them), so "is E11.9 in E08-E13?" and browsing by block were impossible. The tabular file's
-- chapters and sections become rows; each 3-character category points at its section, and
-- deeper codes reach it through parent_code.
--   chapter 4 "Endocrine, nutritional and metabolic diseases" E00-E89
--     section "E08-E13" Diabetes mellitus
--       category E11 -> E11.9
-- Section ids are the tabular file's own (<section id="E08-E13">; a one-category block is
-- written "C7A-C7A" there).

CREATE TABLE icd10_chapter (
    version_id UUID NOT NULL REFERENCES icd10_release(version_id) ON DELETE CASCADE,
    chapter    SMALLINT NOT NULL CHECK (chapter > 0),
    first_code TEXT NOT NULL CHECK (first_code ~ '^[A-Z][0-9][0-9A-Z]$'),
    last_code  TEXT NOT NULL CHECK (last_code ~ '^[A-Z][0-9][0-9A-Z]$'),
    title      TEXT NOT NULL,
    PRIMARY KEY (version_id, chapter),
    CHECK (first_code <= last_code)
);

CREATE TABLE icd10_section (
    version_id UUID NOT NULL REFERENCES icd10_release(version_id) ON DELETE CASCADE,
    id         TEXT NOT NULL CHECK (id ~ '^[A-Z][0-9][0-9A-Z]-[A-Z][0-9][0-9A-Z]$'),
    chapter    SMALLINT NOT NULL,
    first_code TEXT GENERATED ALWAYS AS (split_part(id, '-', 1)) STORED,
    last_code  TEXT GENERATED ALWAYS AS (split_part(id, '-', 2)) STORED,
    title      TEXT NOT NULL,
    PRIMARY KEY (version_id, id),
    FOREIGN KEY (version_id, chapter) REFERENCES icd10_chapter (version_id, chapter) ON DELETE CASCADE,
    CHECK (split_part(id, '-', 1) <= split_part(id, '-', 2))
);

CREATE INDEX icd10_section_chapter ON icd10_section (version_id, chapter, first_code);

ALTER TABLE icd10_code
    ADD COLUMN section_id TEXT,
    ADD CONSTRAINT icd10_code_section_fk FOREIGN KEY (version_id, section_id)
        REFERENCES icd10_section (version_id, id) ON DELETE CASCADE,
    -- Only 3-character categories carry the section; subcodes inherit it via parent_code.
    ADD CONSTRAINT icd10_code_section_on_category CHECK (section_id IS NULL OR code !~ '\.');

CREATE INDEX icd_code_section ON icd10_code (version_id, section_id) WHERE section_id IS NOT NULL;

GRANT INSERT, DELETE ON icd10_chapter, icd10_section TO cp_terms_import;


---- create above / drop below ----


DROP INDEX icd_code_section;
ALTER TABLE icd10_code
    DROP CONSTRAINT icd10_code_section_on_category,
    DROP CONSTRAINT icd10_code_section_fk,
    DROP COLUMN section_id;
DROP TABLE icd10_section;
DROP TABLE icd10_chapter;
