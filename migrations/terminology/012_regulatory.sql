CREATE TABLE meddra_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'meddra' CHECK (code_system = 'meddra'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version (id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE meddra_term_level AS ENUM ('SOC', 'HLGT', 'HLT', 'PT');

CREATE TABLE meddra_term (
    version_id   uuid NOT NULL REFERENCES meddra_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL CHECK (code ~ '^[0-9]{8}$'),  -- '10012601' (Diabetes mellitus)
    level        meddra_term_level NOT NULL,
    name         text NOT NULL,
    abbreviation text,
    PRIMARY KEY (version_id, code),
    UNIQUE (version_id, code, level)
);

CREATE TABLE meddra_llt (
    version_id   uuid NOT NULL REFERENCES meddra_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL CHECK (code ~ '^[0-9]{8}$'),
    name         text NOT NULL,
    pt_code      text NOT NULL,
    current      boolean NOT NULL DEFAULT true,
    pt_level     meddra_term_level GENERATED ALWAYS AS ('PT') STORED,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, pt_code, pt_level)
        REFERENCES meddra_term (version_id, code, level)
        ON DELETE CASCADE
);

CREATE INDEX meddra_llt_by_pt ON meddra_llt (version_id, pt_code);

CREATE TABLE meddra_hierarchy (
    version_id   uuid NOT NULL REFERENCES meddra_release (version_id) ON DELETE CASCADE,
    pt_code       text NOT NULL,
    hlt_code      text NOT NULL,
    hlgt_code     text NOT NULL,
    soc_code      text NOT NULL,
    primary_soc   boolean NOT NULL,
    pt_level      meddra_term_level GENERATED ALWAYS AS ('PT') STORED,
    hlt_level     meddra_term_level GENERATED ALWAYS AS ('HLT') STORED,
    hlgt_level    meddra_term_level GENERATED ALWAYS AS ('HLGT') STORED,
    soc_level     meddra_term_level GENERATED ALWAYS AS ('SOC') STORED,
    PRIMARY KEY (version_id, pt_code, hlt_code, hlgt_code, soc_code),
    FOREIGN KEY (version_id, pt_code, pt_level)
        REFERENCES meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, hlt_code, hlt_level)
        REFERENCES meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, hlgt_code, hlgt_level)
        REFERENCES meddra_term (version_id, code, level)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, soc_code, soc_level)
        REFERENCES meddra_term (version_id, code, level)
        ON DELETE CASCADE
);

CREATE UNIQUE INDEX meddra_hierarchy_one_primary ON meddra_hierarchy (version_id, pt_code) WHERE primary_soc;


---- create above / drop below ----


DROP TABLE meddra_hierarchy;
DROP TABLE meddra_llt;
DROP TABLE meddra_term;
DROP TYPE meddra_term_level;
DROP TABLE meddra_release;
