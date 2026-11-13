CREATE TABLE terms.nanda_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'nanda' CHECK (code_system = 'nanda'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE terms.nanda_dx_type AS ENUM ('problem_focused', 'risk', 'health_promotion', 'syndrome');
CREATE TYPE terms.nanda_dx_indicator_type AS ENUM ('defining_characteristic', 'related_factor', 'risk_factor','at_risk_population', 'associated_condition');

CREATE TABLE terms.nanda_diagnosis (
    version_id UUID NOT NULL REFERENCES terms.nanda_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9]{5}$'),
    label TEXT NOT NULL,
    definition TEXT,
    diagnosis_type terms.nanda_dx_type NOT NULL,
    domain_number SMALLINT NOT NULL,
    domain_name TEXT NOT NULL,
    class_number SMALLINT NOT NULL,
    class_name TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.nanda_diagnosis_indicator (
    version_id UUID NOT NULL REFERENCES terms.nanda_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind terms.nanda_dx_indicator_type NOT NULL,
    sequence SMALLINT NOT NULL,
    text TEXT NOT NULL,
    PRIMARY KEY (version_id, code, kind, sequence),
    FOREIGN KEY (version_id, code)
        REFERENCES terms.nanda_diagnosis (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE terms.nic_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'nic' CHECK (code_system = 'nic'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.nic_intervention (
    version_id UUID NOT NULL REFERENCES terms.nic_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]{4}$' ),
    label TEXT NOT NULL,
    definition TEXT,
    domain_code TEXT NOT NULL,
    domain_name TEXT NOT NULL,
    class_code TEXT NOT NULL,
    class_name TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.nic_activity (
    version_id UUID NOT NULL REFERENCES terms.nic_release(version_id) ON DELETE CASCADE,
    intervention_code TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    activity_code TEXT,
    text TEXT NOT NULL,
    PRIMARY KEY (version_id, intervention_code, sequence),
    FOREIGN KEY (version_id, intervention_code)
        REFERENCES terms.nic_intervention(version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE terms.noc_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'noc' CHECK (code_system = 'noc'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.noc_scale (
    version_id UUID NOT NULL REFERENCES terms.noc_release(version_id) ON DELETE CASCADE,
    scale_code TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (version_id, scale_code)
);

CREATE TABLE terms.noc_scale_level (
    version_id UUID NOT NULL REFERENCES terms.noc_release(version_id) ON DELETE CASCADE,
    scale_code TEXT NOT NULL,
    level SMALLINT NOT NULL CHECK ( level BETWEEN 1 AND 5),
    label TEXT NOT NULL,
    PRIMARY KEY (version_id, scale_code, level),
    FOREIGN KEY (version_id, scale_code)
        REFERENCES terms.noc_scale (version_id, scale_code)
        ON DELETE CASCADE
);

CREATE TABLE terms.noc_outcome (
    version_id UUID NOT NULL REFERENCES terms.noc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]{4}$' ),
    label TEXT NOT NULL,
    definition TEXT,
    domain_code TEXT NOT NULL,
    domain_name TEXT NOT NULL,
    class_code TEXT NOT NULL,
    class_name TEXT,
    scale_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, scale_code)
        REFERENCES terms.noc_scale (version_id, scale_code)
);

CREATE TABLE terms.noc_indicator (
    version_id UUID NOT NULL REFERENCES terms.noc_release(version_id) ON DELETE CASCADE,
    outcome_code TEXT NOT NULL,
    code TEXT NOT NULL,
    text TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    scale_code TEXT,
    PRIMARY KEY (version_id, outcome_code, code),
    FOREIGN KEY (version_id, outcome_code)
        REFERENCES terms.noc_outcome(version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, scale_code)
        REFERENCES terms.noc_scale (version_id, scale_code)
);


CREATE TABLE terms.omaha_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'omaha' CHECK (code_system = 'omaha'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE terms.omaha_concept_type AS ENUM ('domain', 'problem', 'sign_symptom', 'modifier', 'intervention_category', 'target', 'rating_concept', 'rating_level');

CREATE TABLE terms.omaha_concept (
    version_id UUID NOT NULL REFERENCES terms.omaha_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind terms.omaha_concept_type NOT NULL,
    name TEXT NOT NULL,
    definition TEXT,
    parent_code TEXT,
    sequence SMALLINT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code)
        REFERENCES terms.omaha_concept(version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX omaha_concept_kind ON terms.omaha_concept (version_id, kind);


CREATE TABLE terms.pnds_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'pnds' CHECK (code_system = 'pnds'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE terms.pnds_concept_type AS ENUM ('domain', 'diagnosis', 'intervention', 'outcome');

CREATE TABLE terms.pnds_concept (
    version_id UUID NOT NULL REFERENCES terms.pnds_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind terms.pnds_concept_type NOT NULL,
    label TEXT NOT NULL,
    definition TEXT,
    domain_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, domain_code)
        REFERENCES terms.pnds_concept(version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE terms.pnds_outcome_intervention (
    version_id UUID NOT NULL REFERENCES terms.pnds_release(version_id) ON DELETE CASCADE,
    outcome_code TEXT NOT NULL,
    intervention_code TEXT NOT NULL,
    PRIMARY KEY (version_id, outcome_code, intervention_code),
    FOREIGN KEY (version_id, outcome_code)
        REFERENCES terms.pnds_concept (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, intervention_code)
        REFERENCES terms.pnds_concept (version_id, code)
        ON DELETE CASCADE
);