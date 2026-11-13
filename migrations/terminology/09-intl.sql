CREATE TABLE icpc2_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'icpc2' CHECK (code_system = 'icpc2'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE icpc2_code (
    version_id UUID NOT NULL REFERENCES icpc2_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[ABDFHKLNPRSTUWXYZ][0-9]{2}$'),
    chapter TEXT GENERATED ALWAYS AS (left(code, 1)) STORED,
    -- TODO(verify) against the ICPC-2 manual: rubric ranges for each component.
    component SMALLINT GENERATED ALWAYS AS (CASE
        WHEN substring(code, 2, 2)::integer BETWEEN 1 AND 29 THEN 1
        WHEN substring(code, 2, 2)::integer BETWEEN 30 AND 49 THEN 2
        WHEN substring(code, 2, 2)::integer BETWEEN 50 AND 59 THEN 3
        WHEN substring(code, 2, 2)::integer BETWEEN 60 AND 61 THEN 4
        WHEN substring(code, 2, 2)::integer = 62 THEN 5
        WHEN substring(code, 2, 2)::integer BETWEEN 63 AND 69 THEN 6
        WHEN substring(code, 2, 2)::integer BETWEEN 70 AND 99 THEN 7
    END) STORED CHECK ( component BETWEEN 1 AND 7 ),
    title TEXT NOT NULL,
    short_title TEXT,
    inclusion TEXT,
    exclusion TEXT,
    criteria TEXT,
    consider TEXT,
    PRIMARY KEY (version_id, code)
);


CREATE TABLE icpc2plus_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'icpc2plus' CHECK (code_system = 'icpc2plus'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE icpc2plus_term (
    version_id UUID NOT NULL REFERENCES icpc2plus_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    label TEXT NOT NULL,
    icpc2_code TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE INDEX icpc2plus_term_by_icpc2 ON icpc2plus_term (version_id, icpc2_code);


CREATE TABLE icpc2_icd10_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'icpc2_icd10' CHECK (code_system = 'icpc2_icd10'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE icpc2_icd10_term (
    version_id UUID NOT NULL REFERENCES icpc2_icd10_release(version_id) ON DELETE CASCADE,
    term_id TEXT NOT NULL,
    term TEXT NOT NULL,
    icpc2_code TEXT NOT NULL,
    icd10_who TEXT NOT NULL,  -- WHO ICD-10, not ICD-10-CM
    PRIMARY KEY (version_id, term_id)
);

CREATE INDEX icpc2_icd10_term_by_icpc2 ON icpc2_icd10_term (version_id, icpc2_code);
CREATE INDEX icpc2_icd10_term_by_icd10_who ON icpc2_icd10_term (version_id, icd10_who);


CREATE TABLE icf_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'icf' CHECK (code_system = 'icf'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE icf_code (
    version_id UUID NOT NULL REFERENCES icf_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[bsde][0-9]*$' ),
    component TEXT GENERATED ALWAYS AS (left(code, 1)) STORED,
    level SMALLINT NOT NULL,
    title TEXT NOT NULL,
    definition TEXT,
    inclusions TEXT,
    exclusions TEXT,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code)
        REFERENCES icf_code (version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TYPE icf_qualifier_component AS ENUM ('b', 's', 'd', 'e');

CREATE TABLE icf_qualifier_level (
    version_id UUID NOT NULL REFERENCES icf_release(version_id) ON DELETE CASCADE,
    component icf_qualifier_component NOT NULL,
    position SMALLINT NOT NULL,
    value TEXT NOT NULL,
    label TEXT NOT NULL,
    PRIMARY KEY (version_id, component, position, value)
);