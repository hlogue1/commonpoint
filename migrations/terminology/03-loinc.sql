CREATE TABLE loinc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'loinc' CHECK (code_system = 'loinc'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE loinc_class_type AS ENUM ('lab', 'clinical', 'claims_attachment', 'survey');
CREATE TYPE loinc_status AS ENUM ('active', 'trial', 'discouraged', 'deprecated');
CREATE TYPE loinc_order_obs AS ENUM ('order', 'observation', 'both', 'subset');

CREATE TABLE loinc_term (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    loinc_num TEXT NOT NULL CHECK (loinc_num ~ '^[0-9]{1,7}-[0-9]$'),
    component TEXT NOT NULL,
    property TEXT NOT NULL,
    time_aspect TEXT NOT NULL,
    system TEXT NOT NULL,
    scale TEXT NOT NULL,
    method TEXT,
    class TEXT NOT NULL,
    class_type loinc_class_type NOT NULL,
    status loinc_status NOT NULL,
    long_common_name TEXT NOT NULL,
    short_name TEXT,
    display_name TEXT,
    consumer_name TEXT,
    example_ucum_units TEXT,
    order_obs loinc_order_obs,
    PRIMARY KEY (version_id, loinc_num)
) PARTITION BY LIST (version_id);

CREATE INDEX loinc_term_class    ON loinc_term (version_id, class_type, class);
CREATE INDEX loinc_term_lcn_trgm ON loinc_term USING gin (long_common_name gin_trgm_ops);

CREATE TABLE loinc_map_to (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    loinc_num TEXT NOT NULL,
    map_to TEXT NOT NULL,
    comment TEXT,
    PRIMARY KEY (version_id, loinc_num, map_to)
);

CREATE TABLE loinc_answer_list (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    answer_list_id TEXT NOT NULL CHECK (answer_list_id ~ '^LL[0-9]+-[0-9]$'),
    name TEXT NOT NULL,
    oid TEXT,
    ext_defined BOOLEAN NOT NULL DEFAULT FALSE,
    ext_defined_url TEXT,
    PRIMARY KEY (version_id, answer_list_id)
);

CREATE TABLE loinc_answer (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    answer_list_id TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    answer_string_id TEXT NOT NULL CHECK (answer_string_id ~ '^LA[0-9]+-[0-9]$'),
    display TEXT NOT NULL,
    score NUMERIC,
    ext_code_system TEXT,
    ext_code TEXT,
    local_answer_code TEXT,
    local_answer_code_system TEXT,
    ext_code_display TEXT,
    ext_code_system_version TEXT,
    PRIMARY KEY (version_id, answer_list_id, sequence),
    FOREIGN KEY (version_id, answer_list_id) REFERENCES loinc_answer_list(version_id, answer_list_id) ON DELETE CASCADE
);

CREATE TYPE loinc_term_answer_list_binding AS ENUM ('normative', 'preferred', 'example');

CREATE TABLE loinc_term_answer_list (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    loinc_num TEXT NOT NULL,
    answer_list_id TEXT NOT NULL,
    binding loinc_term_answer_list_binding NOT NULL,
    applicable_context TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (version_id, loinc_num, answer_list_id, applicable_context),
    FOREIGN KEY (version_id, loinc_num) REFERENCES loinc_term(version_id, loinc_num) ON DELETE CASCADE,
    FOREIGN KEY (version_id, answer_list_id) REFERENCES loinc_answer_list(version_id, answer_list_id) ON DELETE CASCADE
);

CREATE TYPE loinc_observation_required AS ENUM ('required', 'optional', 'conditional');

-- TODO(verify): check whether PanelsAndForms.csv repeats (ParentLoinc, SEQUENCE) for
-- sub-panels shared between top-level panels. If it does, the PK below rejects real rows:
-- rekey on the file's row id (add row_id integer NOT NULL, parent_row_id integer,
-- top_panel_loinc_num text NOT NULL; PK (version_id, row_id); index (version_id, panel_loinc_num)).
CREATE TABLE loinc_panel_member (
    version_id UUID NOT NULL REFERENCES loinc_release(version_id) ON DELETE CASCADE,
    panel_loinc_num TEXT NOT NULL,
    member_loinc_num TEXT NOT NULL,
    sequence SMALLINT NOT NULL,
    observation_required loinc_observation_required,
    PRIMARY KEY (version_id, panel_loinc_num, sequence),
    FOREIGN KEY (version_id, panel_loinc_num) REFERENCES loinc_term(version_id, loinc_num) ON DELETE CASCADE,
    FOREIGN KEY (version_id, member_loinc_num) REFERENCES loinc_term(version_id, loinc_num) ON DELETE CASCADE
);

CREATE INDEX loinc_panel_member_member ON loinc_panel_member (version_id, member_loinc_num);