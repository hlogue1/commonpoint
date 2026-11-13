CREATE TABLE terms.meddra_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'meddra' CHECK (code_system = 'meddra'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version (id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE terms.meddra_term_level AS ENUM ('SOC', 'HLGT', 'HLT', 'PT');

CREATE TABLE terms.meddra_term (
    version_id   uuid NOT NULL REFERENCES terms.meddra_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL CHECK (code ~ '^[0-9]{8}$'),  -- '10012601' (Diabetes mellitus)
    level        terms.meddra_term_level NOT NULL,
    name         text NOT NULL,
    abbreviation text,
    PRIMARY KEY (version_id, code),
    UNIQUE (version_id, code, level)
);

CREATE TABLE terms.meddra_llt (
    version_id   uuid NOT NULL REFERENCES terms.meddra_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL CHECK (code ~ '^[0-9]{8}$'),
    name         text NOT NULL,
    pt_code      text NOT NULL,
    current      boolean NOT NULL DEFAULT true,
    pt_level     terms.meddra_term_level GENERATED ALWAYS AS ('PT') STORED,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, pt_code, pt_level)
        REFERENCES terms.meddra_term (version_id, code, level)
        ON DELETE CASCADE
);

CREATE INDEX meddra_llt_by_pt ON terms.meddra_llt (version_id, pt_code);

CREATE TABLE terms.meddra_hierarchy (
    version_id   uuid NOT NULL REFERENCES terms.meddra_release (version_id) ON DELETE CASCADE,
    pt_code       text NOT NULL,
    hlt_code      text NOT NULL,
    hlgt_code     text NOT NULL,
    soc_code      text NOT NULL,
    primary_soc   boolean NOT NULL,
    pt_level      terms.meddra_term_level GENERATED ALWAYS AS ('PT') STORED,
    hlt_level     terms.meddra_term_level GENERATED ALWAYS AS ('HLT') STORED,
    hlgt_level    terms.meddra_term_level GENERATED ALWAYS AS ('HLGT') STORED,
    soc_level     terms.meddra_term_level GENERATED ALWAYS AS ('SOC') STORED,
    PRIMARY KEY (version_id, pt_code, hlt_code, hlgt_code, soc_code),
    FOREIGN KEY (version_id, pt_code, pt_level)
        REFERENCES terms.meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, hlt_code, hlt_level)
        REFERENCES terms.meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, hlgt_code, hlgt_level)
        REFERENCES terms.meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, soc_code, soc_level)
        REFERENCES terms.meddra_term (version_id, code, level)
        ON DELETE CASCADE
);

CREATE UNIQUE INDEX meddra_hierarchy_one_primary ON terms.meddra_hierarchy (version_id, pt_code) WHERE primary_soc;