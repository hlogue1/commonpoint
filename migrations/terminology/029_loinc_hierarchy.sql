-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C11: LOINC had no hierarchy, so Subsumes/Traverse and is-a value-set filters couldn't
-- work for it. LOINC publishes one as the multiaxial hierarchy accessory file
-- (MultiAxialHierarchy.csv: PATH_TO_ROOT, SEQUENCE, IMMEDIATE_PARENT, CODE, CODE_TEXT).
--
-- * loinc_hierarchy stores the file's rows. Nodes are LOINC parts (LP...) and LOINC terms, and a
--   code can sit under several parents, so a row is keyed by (code, path_to_root). There is no
--   FK to loinc_term: most nodes are parts, not terms.
-- * loinc_closure is derived by the loader from it: ancestor/descendant pairs with the minimum
--   depth, non-reflexive like snomed_closure. loinc_subsumes() answers the a = b case.
-- Both are partitioned by version_id and owned by cp_terms_import, like every content family;
-- attach loinc_hierarchy and loinc_closure in any order (neither references another
-- partitioned table).

CREATE TABLE loinc_hierarchy (
    version_id       UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    path_to_root     TEXT NOT NULL DEFAULT '',  -- dotted ancestor codes, '' for a root
    sequence         INTEGER NOT NULL,
    immediate_parent TEXT,
    code             TEXT NOT NULL,
    code_text        TEXT NOT NULL,
    PRIMARY KEY (version_id, code, path_to_root)
) PARTITION BY LIST (version_id);

CREATE INDEX loinc_hierarchy_parent ON loinc_hierarchy (version_id, immediate_parent, sequence);

CREATE TABLE loinc_closure (
    version_id    UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    ancestor      TEXT NOT NULL,
    descendant    TEXT NOT NULL,
    depth         SMALLINT NOT NULL CHECK (depth > 0),
    PRIMARY KEY (version_id, ancestor, descendant),
    CHECK (ancestor <> descendant)
) PARTITION BY LIST (version_id);

CREATE INDEX loinc_closure_up ON loinc_closure (version_id, descendant);

CREATE FUNCTION loinc_subsumes(p_version_id UUID, p_ancestor TEXT, p_descendant TEXT)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT p_ancestor = p_descendant OR EXISTS (
    SELECT 1 FROM loinc_closure
    WHERE version_id = p_version_id AND ancestor = p_ancestor AND descendant = p_descendant)
$$;

ALTER TABLE loinc_hierarchy OWNER TO cp_terms_import;
ALTER TABLE loinc_closure OWNER TO cp_terms_import;
REVOKE TRUNCATE ON loinc_hierarchy, loinc_closure FROM cp_terms_import;
GRANT SELECT ON loinc_hierarchy, loinc_closure TO cp_terms_app;


---- create above / drop below ----


DROP FUNCTION loinc_subsumes(uuid, text, text);
DROP TABLE loinc_closure;
DROP TABLE loinc_hierarchy;
