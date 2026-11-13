-- Per-release load pattern for tables declared PARTITION BY LIST (version_id): every
-- snomed_*, rxnorm_*, loinc_*, ncit_*, hpo_* and mondo_* table except the *_release tables.
-- Partitioned tables accept no rows until a partition exists. rxnorm_history has a UNIQUE
-- constraint instead of a primary key, so build that unique index on its partition rather
-- than a primary key.
--
--   CREATE TABLE <t>_<release> (LIKE <t> INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED);
--   ALTER TABLE <t>_<release> ADD CHECK (version_id = '<version uuid>');
--   COPY <t>_<release> FROM ...;
--   -- create the primary key and the indexes declared on the parent
--   ANALYZE <t>_<release>;
--   ALTER TABLE <t> ATTACH PARTITION <t>_<release> FOR VALUES IN ('<version uuid>');
--
-- FKs are checked at ATTACH, so attach a referenced table before the tables that reference it.
-- For SNOMED: snomed_concept, then snomed_description, snomed_relationship, snomed_extended_map,
-- snomed_core_problem_list, then snomed_language_member (it references snomed_description).
-- The remaining SNOMED tables have no FK into another partitioned table and can attach in any order.
-- For the other families, attach these first and the rest in any order:
--   RxNorm: rxnorm_concept
--   LOINC:  loinc_term and loinc_answer_list
--   NCIt:   ncit_concept
--   HPO:    hpo_term
--   Mondo:  mondo_term
--
-- Retire a release with DETACH + DROP, in the reverse order. Every partitioned family is
-- self-contained, so no rows need deleting first. Code systems that are not partitioned are
-- retired by deleting their *_release row, which cascades.
--
-- snomed_concept has one extra load step: its module_id FK is declared on each partition, not on
-- the parent, because a parent-level self-FK makes DETACH fail while the partition has rows.
-- After creating the primary key and before ATTACH, run:
--   ALTER TABLE snomed_concept_<release>
--       ADD CONSTRAINT snomed_concept_<release>_module_fk
--       FOREIGN KEY (version_id, module_id)
--       REFERENCES snomed_concept_<release> (version_id, id)
--       ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
-- Nothing in the schema enforces this step, so the loader must not skip it.

CREATE TABLE snomed_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'snomed' CHECK (code_system = 'snomed'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE snomed_concept (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    module_id BIGINT NOT NULL,
    fully_defined BOOLEAN NOT NULL,
    fsn TEXT NOT NULL,
    preferred_term_en_us TEXT NOT NULL,  -- display cache of the en-US preferred synonym; snomed_language_member is authoritative
    semantic_tag TEXT NOT NULL,
    PRIMARY KEY (version_id, id)
) PARTITION BY LIST (version_id);

-- module_id FK: declared per partition by the loader; see the load pattern at the top of this file.

-- concept_index exposes id::text as its code column; this index serves those lookups.
CREATE INDEX snomed_concept_code_text ON snomed_concept (version_id, (id::text));
CREATE INDEX snomed_concept_semantic_tag ON snomed_concept (version_id, semantic_tag) WHERE active;

CREATE TYPE snomed_description_type AS ENUM ('fsn', 'synonym', 'definition');
CREATE TYPE snomed_acceptability_level AS ENUM ('preferred', 'acceptable');

CREATE TABLE snomed_description (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    concept_id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    module_id BIGINT NOT NULL,
    language_code TEXT NOT NULL,
    type snomed_description_type NOT NULL,
    term TEXT NOT NULL,
    case_significance_id BIGINT NOT NULL CHECK (case_significance_id IN (900000000000448009, 900000000000017005, 900000000000020002)),
    PRIMARY KEY (version_id, id),
    FOREIGN KEY (version_id, concept_id)
        REFERENCES snomed_concept(version_id, id)
        ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_description_concept ON snomed_description (version_id, concept_id);
CREATE INDEX snomed_description_trgm    ON snomed_description USING gin (term gin_trgm_ops);

CREATE TABLE snomed_language_member (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    refset_id BIGINT NOT NULL,
    description_id BIGINT NOT NULL,
    acceptability snomed_acceptability_level NOT NULL,
    PRIMARY KEY (version_id, refset_id, description_id),
    FOREIGN KEY (version_id, description_id)
        REFERENCES snomed_description (version_id, id)
        ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE TABLE snomed_relationship (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    source_id BIGINT NOT NULL,
    type_id BIGINT NOT NULL,
    destination_id BIGINT NOT NULL,
    rel_group SMALLINT NOT NULL DEFAULT 0,
    characteristic_type_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, id),
    FOREIGN KEY (version_id, source_id) REFERENCES snomed_concept(version_id, id) ON DELETE CASCADE,
    FOREIGN KEY (version_id, type_id) REFERENCES snomed_concept(version_id, id) ON DELETE CASCADE,
    FOREIGN KEY (version_id, destination_id) REFERENCES snomed_concept(version_id, id) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_relationship_source ON snomed_relationship (version_id, source_id, type_id) WHERE active;
CREATE INDEX snomed_relationship_destination ON snomed_relationship (version_id, destination_id, type_id) WHERE active;

CREATE TABLE snomed_relationship_concrete (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    source_id BIGINT NOT NULL,
    type_id BIGINT NOT NULL,
    value TEXT NOT NULL,
    rel_group SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (version_id, id)
) PARTITION BY LIST (version_id);

CREATE TABLE snomed_refset_member (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    refset_id BIGINT NOT NULL,
    referenced_component_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, refset_id, referenced_component_id)
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_refset_member_component ON snomed_refset_member (version_id, referenced_component_id);

CREATE TABLE snomed_closure (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    ancestor_id BIGINT NOT NULL,
    descendant_id BIGINT NOT NULL,
    depth SMALLINT NOT NULL,
    PRIMARY KEY (version_id, ancestor_id, descendant_id)
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_closure_up ON snomed_closure (version_id, descendant_id);

CREATE TABLE snomed_history (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    inactive_id BIGINT NOT NULL,
    association_refset_id BIGINT NOT NULL,
    target_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, inactive_id, association_refset_id, target_id)
) PARTITION BY LIST (version_id);

CREATE TABLE snomed_extended_map (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    refset_id BIGINT NOT NULL,
    concept_id BIGINT NOT NULL,
    map_group SMALLINT NOT NULL,
    map_priority SMALLINT NOT NULL,
    map_rule TEXT NOT NULL,
    map_advice TEXT,
    target_code TEXT,
    map_category BIGINT,
    correlation_id BIGINT,
    PRIMARY KEY (version_id, refset_id, concept_id, map_group, map_priority),
    FOREIGN KEY (version_id, concept_id) REFERENCES snomed_concept(version_id, id) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_extended_map_target ON snomed_extended_map (version_id, target_code);

CREATE TABLE snomed_core_problem_list (
    version_id UUID NOT NULL REFERENCES snomed_release(version_id) ON DELETE CASCADE,
    concept_id BIGINT NOT NULL,
    usage_rank NUMERIC,
    first_in_subset TEXT,
    last_in_subset TEXT,
    is_retired BOOLEAN,
    replaced_by_concept_id BIGINT,
    PRIMARY KEY (version_id, concept_id),
    -- CORE concepts include US Extension content, so this FK requires the US Edition to be loaded.
    FOREIGN KEY (version_id, concept_id) REFERENCES snomed_concept(version_id, id) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

-- snomed_closure does not store reflexive rows (ancestor_id = descendant_id); a concept
-- subsumes itself by definition, so the function answers that case without the table.
CREATE FUNCTION snomed_subsumes(p_version_id UUID, p_ancestor BIGINT, p_descendant BIGINT)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT p_ancestor = p_descendant OR EXISTS (
    SELECT 1 FROM snomed_closure
    WHERE version_id = p_version_id AND ancestor_id = p_ancestor AND descendant_id = p_descendant)
$$;