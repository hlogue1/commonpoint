CREATE TABLE icd10_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'icd10cm' CHECK (code_system = 'icd10cm'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE icd10_code (
    version_id UUID NOT NULL REFERENCES icd10_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[A-Z][0-9][0-9A-Z](\.[0-9A-Z]{1,4})?$'),
    code_compact   text GENERATED ALWAYS AS (replace(code, '.', '')) STORED,
    billable BOOLEAN NOT NULL,
    short_desc TEXT NOT NULL,
    long_desc TEXT NOT NULL,
    parent_code TEXT,
    chapter SMALLINT,
    PRIMARY KEY (version_id, code),
    UNIQUE (version_id, code_compact),
    FOREIGN KEY (version_id, parent_code)
        REFERENCES icd10_code (version_id, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX icd_code_parent   ON icd10_code (version_id, parent_code);
CREATE INDEX icd_code_long_trgm ON icd10_code USING gin (long_desc gin_trgm_ops);

CREATE TYPE icd10_note_type AS ENUM ('inclusion_term', 'includes', 'excludes1', 'excludes2', 'code_first', 'use_additional_code', 'code_also', 'seven_chr_note');
CREATE TYPE icd10_note_scope AS ENUM ('chapter', 'section', 'code');

CREATE TABLE icd10_note (
    version_id UUID NOT NULL REFERENCES icd10_release(version_id) ON DELETE CASCADE,
    scope icd10_note_scope NOT NULL,
    ref TEXT NOT NULL,
    note_type icd10_note_type NOT NULL,
    sequence SMALLINT NOT NULL,
    text TEXT NOT NULL,
    PRIMARY KEY (version_id, scope, ref, note_type, sequence)
);

CREATE TABLE icd10_seven_chr (
    version_id UUID NOT NULL REFERENCES icd10_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    character CHAR(1) NOT NULL,
    description TEXT NOT NULL,
    PRIMARY KEY (version_id, code, character)
);

CREATE TABLE icd_pcs_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'icd10pcs' CHECK (code_system = 'icd10pcs'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE icd_pcs_code (
    version_id UUID NOT NULL REFERENCES icd_pcs_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9A-HJ-NP-Z]{7}$'),
    billable BOOLEAN NOT NULL,
    short_desc TEXT NOT NULL,
    long_desc TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE cpt_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cpt' CHECK (code_system = 'cpt'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE cpt_code_type AS ENUM ('I', 'II', 'III', 'PLA');

CREATE TABLE cpt_code (
    version_id UUID NOT NULL REFERENCES cpt_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9]{4}[0-9FTMU]$'),
    category cpt_code_type NOT NULL,
    reportable BOOLEAN NOT NULL DEFAULT TRUE,
    long_descriptor TEXT NOT NULL,
    med_descriptor TEXT,
    short_descriptor TEXT,
    consumer_descriptor TEXT,
    section_path TEXT,
    PRIMARY KEY (version_id, code)
);

CREATE INDEX cpt_code_long_trgm ON cpt_code USING gin (long_descriptor gin_trgm_ops);

CREATE TABLE cpt_clinician_descriptor (
    version_id UUID NOT NULL REFERENCES cpt_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    descriptor_id SMALLINT NOT NULL,  -- TODO(verify): confirm the AMA file's Clinician Descriptor Id fits smallint; widen to integer if not
    descriptor TEXT NOT NULL,
    PRIMARY KEY (version_id, code, descriptor_id),
    FOREIGN KEY (version_id, code) REFERENCES cpt_code(version_id, code) ON DELETE CASCADE
);

CREATE TABLE cpt_modifier (
    version_id UUID NOT NULL REFERENCES cpt_release(version_id) ON DELETE CASCADE,
    modifier TEXT NOT NULL CHECK (modifier ~ '^[0-9A-Z]{2}$'),
    descriptor TEXT NOT NULL,
    PRIMARY KEY (version_id, modifier)
);

CREATE TABLE hcpcs_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'hcpcs' CHECK (code_system = 'hcpcs'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE hcpcs_code (
    version_id UUID NOT NULL REFERENCES hcpcs_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[A-V][0-9]{4}$'),
    short_desc TEXT NOT NULL,
    long_desc TEXT NOT NULL,
    validity daterange,
    PRIMARY KEY (version_id, code)
);

CREATE INDEX hcpcs_code_long_trgm ON hcpcs_code USING gin (long_desc gin_trgm_ops);

CREATE TABLE hcpcs_modifier (
    version_id UUID NOT NULL REFERENCES hcpcs_release(version_id) ON DELETE CASCADE,
    modifier TEXT NOT NULL CHECK (modifier ~ '^[0-9A-Z]{2}$'),
    descriptor TEXT NOT NULL,
    PRIMARY KEY (version_id, modifier)
);

CREATE TABLE cdt_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cdt' CHECK (code_system = 'cdt'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE cdt_code (
    version_id UUID NOT NULL REFERENCES cdt_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^D[0-9]{4}$' ),
    category TEXT NOT NULL,
    nomenclature TEXT NOT NULL,
    descriptor TEXT,
    PRIMARY KEY (version_id, code)
);

CREATE INDEX cdt_code_nomenclature_trgm ON cdt_code USING gin (nomenclature gin_trgm_ops);

CREATE TABLE icd9_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'icd9cm' CHECK (code_system = 'icd9cm'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE icd9_type AS ENUM ('diagnosis', 'procedure');

CREATE TABLE icd9_code (
    version_id UUID NOT NULL REFERENCES icd9_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    kind icd9_type NOT NULL,
    billable BOOLEAN NOT NULL,
    short_desc TEXT NOT NULL,
    long_desc TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, kind, code),
    FOREIGN KEY (version_id, kind, parent_code)
        REFERENCES icd9_code (version_id, kind, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TYPE icd9_map_type AS ENUM ('icd9_to_icd10', 'icd10_to_icd9');

CREATE TABLE icd9_gem (
    version_id UUID NOT NULL REFERENCES icd9_release(version_id) ON DELETE CASCADE,
    direction icd9_map_type NOT NULL,
    kind icd9_type NOT NULL,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    approximate BOOLEAN NOT NULL,
    no_map BOOLEAN NOT NULL,
    combination BOOLEAN NOT NULL,
    scenario SMALLINT NOT NULL DEFAULT 0,
    choice_list SMALLINT NOT NULL DEFAULT 0,
    PRIMARY KEY (version_id, direction, kind, source, target, scenario, choice_list)
);

CREATE INDEX icd9cm_gem_target ON icd9_gem (version_id, direction, target);

CREATE TABLE abc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'abc' CHECK (code_system = 'abc'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE abc_code (
    version_id UUID NOT NULL REFERENCES abc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( length(code) = 5 ),
    short_desc TEXT,
    descriptor TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES abc_code (version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE sop_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'sop' CHECK (code_system = 'sop'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE sop_code (
    version_id UUID NOT NULL REFERENCES sop_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]+$' ),
    display TEXT NOT NULL,
    level SMALLINT GENERATED ALWAYS AS (length(code)) STORED,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES sop_code (version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE ncci_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ncci' CHECK (code_system = 'ncci'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE ncci_add_on (
    version_id uuid NOT NULL REFERENCES ncci_release ON DELETE CASCADE,
    add_on_code text NOT NULL,
    primary_code text NOT NULL,
    primary_code_system citext NOT NULL CHECK (primary_code_system IN ('cpt', 'hcpcs')),
    edit_type smallint NOT NULL,
    PRIMARY KEY (version_id, add_on_code, primary_code)
);


---- create above / drop below ----


DROP TABLE ncci_add_on;
DROP TABLE ncci_release;
DROP TABLE sop_code;
DROP TABLE sop_release;
DROP TABLE abc_code;
DROP TABLE abc_release;
DROP TABLE icd9_gem;
DROP TYPE icd9_map_type;
DROP TABLE icd9_code;
DROP TYPE icd9_type;
DROP TABLE icd9_release;
DROP TABLE cdt_code;
DROP TABLE cdt_release;
DROP TABLE hcpcs_modifier;
DROP TABLE hcpcs_code;
DROP TABLE hcpcs_release;
DROP TABLE cpt_modifier;
DROP TABLE cpt_clinician_descriptor;
DROP TABLE cpt_code;
DROP TYPE cpt_code_type;
DROP TABLE cpt_release;
DROP TABLE icd_pcs_code;
DROP TABLE icd_pcs_release;
DROP TABLE icd10_seven_chr;
DROP TABLE icd10_note;
DROP TYPE icd10_note_scope;
DROP TYPE icd10_note_type;
DROP TABLE icd10_code;
DROP TABLE icd10_release;
