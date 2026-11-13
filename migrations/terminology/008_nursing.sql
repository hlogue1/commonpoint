CREATE TABLE nanda_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'nanda' CHECK (code_system = 'nanda'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE nanda_dx_type AS ENUM ('problem_focused', 'risk', 'health_promotion', 'syndrome');
CREATE TYPE nanda_dx_indicator_type AS ENUM ('defining_characteristic', 'related_factor', 'risk_factor','at_risk_population', 'associated_condition');

CREATE TABLE nanda_diagnosis (
    version_id UUID NOT NULL REFERENCES nanda_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9]{5}$'),
    label TEXT NOT NULL,
    definition TEXT,
    diagnosis_type nanda_dx_type NOT NULL,
    domain_number SMALLINT NOT NULL,
    domain_name TEXT NOT NULL,
    class_number SMALLINT NOT NULL,
    class_name TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE nanda_diagnosis_indicator (
    version_id UUID NOT NULL REFERENCES nanda_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind nanda_dx_indicator_type NOT NULL,
    sequence SMALLINT NOT NULL,
    text TEXT NOT NULL,
    PRIMARY KEY (version_id, code, kind, sequence),
    FOREIGN KEY (version_id, code)
        REFERENCES nanda_diagnosis (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE nic_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'nic' CHECK (code_system = 'nic'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE nic_intervention (
    version_id UUID NOT NULL REFERENCES nic_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]{4}$' ),
    label TEXT NOT NULL,
    definition TEXT,
    domain_code TEXT NOT NULL,
    domain_name TEXT NOT NULL,
    class_code TEXT NOT NULL,
    class_name TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE nic_activity (
    version_id UUID NOT NULL REFERENCES nic_release(version_id) ON DELETE CASCADE,
    intervention_code TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    activity_code TEXT,
    text TEXT NOT NULL,
    PRIMARY KEY (version_id, intervention_code, sequence),
    FOREIGN KEY (version_id, intervention_code)
        REFERENCES nic_intervention(version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE noc_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'noc' CHECK (code_system = 'noc'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE noc_scale (
    version_id UUID NOT NULL REFERENCES noc_release(version_id) ON DELETE CASCADE,
    scale_code TEXT NOT NULL,
    name TEXT NOT NULL,
    PRIMARY KEY (version_id, scale_code)
);

CREATE TABLE noc_scale_level (
    version_id UUID NOT NULL REFERENCES noc_release(version_id) ON DELETE CASCADE,
    scale_code TEXT NOT NULL,
    level SMALLINT NOT NULL CHECK ( level BETWEEN 1 AND 5),
    label TEXT NOT NULL,
    PRIMARY KEY (version_id, scale_code, level),
    FOREIGN KEY (version_id, scale_code)
        REFERENCES noc_scale (version_id, scale_code)
        ON DELETE CASCADE
);

CREATE TABLE noc_outcome (
    version_id UUID NOT NULL REFERENCES noc_release(version_id) ON DELETE CASCADE,
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
        REFERENCES noc_scale (version_id, scale_code)
);

CREATE TABLE noc_indicator (
    version_id UUID NOT NULL REFERENCES noc_release(version_id) ON DELETE CASCADE,
    outcome_code TEXT NOT NULL,
    code TEXT NOT NULL,
    text TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    scale_code TEXT,
    PRIMARY KEY (version_id, outcome_code, code),
    FOREIGN KEY (version_id, outcome_code)
        REFERENCES noc_outcome(version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, scale_code)
        REFERENCES noc_scale (version_id, scale_code)
);


CREATE TABLE omaha_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'omaha' CHECK (code_system = 'omaha'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE omaha_concept_type AS ENUM ('domain', 'problem', 'sign_symptom', 'modifier', 'intervention_category', 'target', 'rating_concept', 'rating_level');

CREATE TABLE omaha_concept (
    version_id UUID NOT NULL REFERENCES omaha_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind omaha_concept_type NOT NULL,
    name TEXT NOT NULL,
    definition TEXT,
    parent_code TEXT,
    sequence SMALLINT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code)
        REFERENCES omaha_concept(version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX omaha_concept_kind ON omaha_concept (version_id, kind);


CREATE TABLE pnds_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'pnds' CHECK (code_system = 'pnds'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE pnds_concept_type AS ENUM ('domain', 'diagnosis', 'intervention', 'outcome');

CREATE TABLE pnds_concept (
    version_id UUID NOT NULL REFERENCES pnds_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind pnds_concept_type NOT NULL,
    label TEXT NOT NULL,
    definition TEXT,
    domain_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, domain_code)
        REFERENCES pnds_concept(version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE pnds_outcome_intervention (
    version_id UUID NOT NULL REFERENCES pnds_release(version_id) ON DELETE CASCADE,
    outcome_code TEXT NOT NULL,
    intervention_code TEXT NOT NULL,
    PRIMARY KEY (version_id, outcome_code, intervention_code),
    FOREIGN KEY (version_id, outcome_code)
        REFERENCES pnds_concept (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, intervention_code)
        REFERENCES pnds_concept (version_id, code)
        ON DELETE CASCADE
);


---- create above / drop below ----


DROP TABLE pnds_outcome_intervention;
DROP TABLE pnds_concept;
DROP TYPE pnds_concept_type;
DROP TABLE pnds_release;
DROP TABLE omaha_concept;
DROP TYPE omaha_concept_type;
DROP TABLE omaha_release;
DROP TABLE noc_indicator;
DROP TABLE noc_outcome;
DROP TABLE noc_scale_level;
DROP TABLE noc_scale;
DROP TABLE noc_release;
DROP TABLE nic_activity;
DROP TABLE nic_intervention;
DROP TABLE nic_release;
DROP TABLE nanda_diagnosis_indicator;
DROP TABLE nanda_diagnosis;
DROP TYPE nanda_dx_indicator_type;
DROP TYPE nanda_dx_type;
DROP TABLE nanda_release;
