-- Per-release load pattern for tables declared PARTITION BY LIST (version_id)
-- (snomed_concept/description/relationship/closure, rxnorm_concept/drug_ingredient/ndc,
-- loinc_term, ncit_concept/synonym). Partitioned tables accept no rows until a
-- partition exists.
--
--   CREATE TABLE terms.<t>_<release> (LIKE terms.<t> INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED);
--   ALTER TABLE terms.<t>_<release> ADD CHECK (version_id = '<version uuid>');
--   COPY terms.<t>_<release> FROM ...;
--   -- create the primary key and the indexes declared on the parent
--   ANALYZE terms.<t>_<release>;
--   ALTER TABLE terms.<t> ATTACH PARTITION terms.<t>_<release> FOR VALUES IN ('<version uuid>');
--
-- FKs are checked at ATTACH, so attach a referenced table before the tables that reference it
-- (snomed_concept before snomed_description, and so on).
--
-- Retire a release with DETACH + DROP, in the reverse order. DETACH fails while any row still
-- references the partition, so first delete that version's rows from the unpartitioned tables
-- with FKs into it (for example snomed_language_member, snomed_extended_map,
-- snomed_core_problem_list, rxnorm_drug, rxnorm_pack_member, loinc_term_answer_list,
-- loinc_panel_member, ncit_parent, ncit_subset_member).
--
-- snomed_concept has one extra load step: its module_id FK is declared on each partition, not on
-- the parent, because a parent-level self-FK makes DETACH fail while the partition has rows.
-- After creating the primary key and before ATTACH, run:
--   ALTER TABLE terms.snomed_concept_<release>
--       ADD CONSTRAINT snomed_concept_<release>_module_fk
--       FOREIGN KEY (version_id, module_id)
--       REFERENCES terms.snomed_concept_<release> (version_id, id)
--       ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;
-- Nothing in the schema enforces this step, so the loader must not skip it.

CREATE TABLE terms.snomed_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'snomed' CHECK (code_system = 'snomed'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.snomed_concept (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
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

-- terms.concept_index exposes id::text as its code column; this index serves those lookups.
CREATE INDEX snomed_concept_code_text ON terms.snomed_concept (version_id, (id::text));
CREATE INDEX snomed_concept_semantic_tag ON terms.snomed_concept (version_id, semantic_tag) WHERE active;

CREATE TYPE terms.snomed_description_type AS ENUM ('fsn', 'synonym', 'definition');
CREATE TYPE terms.snomed_acceptability_level AS ENUM ('preferred', 'acceptable');

CREATE TABLE terms.snomed_description (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    concept_id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    module_id BIGINT NOT NULL,
    language_code TEXT NOT NULL,
    type terms.snomed_description_type NOT NULL,
    term TEXT NOT NULL,
    case_significance_id BIGINT NOT NULL CHECK (case_significance_id IN (900000000000448009, 900000000000017005, 900000000000020002)),
    PRIMARY KEY (version_id, id),
    FOREIGN KEY (version_id, concept_id)
        REFERENCES terms.snomed_concept(version_id, id)
        ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_description_concept ON terms.snomed_description (version_id, concept_id);
CREATE INDEX snomed_description_trgm    ON terms.snomed_description USING gin (term gin_trgm_ops);

CREATE TABLE terms.snomed_language_member (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    refset_id BIGINT NOT NULL,
    description_id BIGINT NOT NULL,
    acceptability terms.snomed_acceptability_level NOT NULL,
    PRIMARY KEY (version_id, refset_id, description_id),
    FOREIGN KEY (version_id, description_id)
        REFERENCES terms.snomed_description (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE terms.snomed_relationship (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    source_id BIGINT NOT NULL,
    type_id BIGINT NOT NULL,
    destination_id BIGINT NOT NULL,
    rel_group SMALLINT NOT NULL DEFAULT 0,
    characteristic_type_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, id),
    FOREIGN KEY (version_id, source_id) REFERENCES terms.snomed_concept(version_id, id) ON DELETE CASCADE,
    FOREIGN KEY (version_id, type_id) REFERENCES terms.snomed_concept(version_id, id) ON DELETE CASCADE,
    FOREIGN KEY (version_id, destination_id) REFERENCES terms.snomed_concept(version_id, id) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_relationship_source ON terms.snomed_relationship (version_id, source_id, type_id) WHERE active;
CREATE INDEX snomed_relationship_destination ON terms.snomed_relationship (version_id, destination_id, type_id) WHERE active;

CREATE TABLE terms.snomed_relationship_concrete (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    id BIGINT NOT NULL,
    active BOOLEAN NOT NULL,
    source_id BIGINT NOT NULL,
    type_id BIGINT NOT NULL,
    value TEXT NOT NULL,
    rel_group SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (version_id, id)
);

CREATE TABLE terms.snomed_refset_member (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    refset_id BIGINT NOT NULL,
    referenced_component_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, refset_id, referenced_component_id)
);

CREATE INDEX snomed_refset_member_component ON terms.snomed_refset_member (version_id, referenced_component_id);

CREATE TABLE terms.snomed_closure (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    ancestor_id BIGINT NOT NULL,
    descendant_id BIGINT NOT NULL,
    depth SMALLINT NOT NULL,
    PRIMARY KEY (version_id, ancestor_id, descendant_id)
) PARTITION BY LIST (version_id);

CREATE INDEX snomed_closure_up ON terms.snomed_closure (version_id, descendant_id);

CREATE TABLE terms.snomed_history (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    inactive_id BIGINT NOT NULL,
    association_refset_id BIGINT NOT NULL,
    target_id BIGINT NOT NULL,
    PRIMARY KEY (version_id, inactive_id, association_refset_id, target_id)
);

CREATE TABLE terms.snomed_extended_map (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
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
    FOREIGN KEY (version_id, concept_id) REFERENCES terms.snomed_concept(version_id, id) ON DELETE CASCADE
);

CREATE INDEX snomed_extended_map_target ON terms.snomed_extended_map (version_id, target_code);

CREATE TABLE terms.snomed_core_problem_list (
    version_id UUID NOT NULL REFERENCES terms.snomed_release(version_id) ON DELETE CASCADE,
    concept_id BIGINT NOT NULL,
    usage_rank NUMERIC,
    first_in_subset TEXT,
    last_in_subset TEXT,
    is_retired BOOLEAN,
    replaced_by_concept_id BIGINT,
    PRIMARY KEY (version_id, concept_id),
    -- CORE concepts include US Extension content, so this FK requires the US Edition to be loaded.
    FOREIGN KEY (version_id, concept_id) REFERENCES terms.snomed_concept(version_id, id) ON DELETE CASCADE
);

-- snomed_closure does not store reflexive rows (ancestor_id = descendant_id); a concept
-- subsumes itself by definition, so the function answers that case without the table.
CREATE FUNCTION terms.snomed_subsumes(p_version_id UUID, p_ancestor BIGINT, p_descendant BIGINT)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT p_ancestor = p_descendant OR EXISTS (
    SELECT 1 FROM terms.snomed_closure
    WHERE version_id = p_version_id AND ancestor_id = p_ancestor AND descendant_id = p_descendant)
$$;