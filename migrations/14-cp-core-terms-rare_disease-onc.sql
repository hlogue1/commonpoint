CREATE TABLE terms.mondo_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'mondo' CHECK (code_system = 'mondo'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.mondo_term (
    version_id UUID NOT NULL REFERENCES terms.mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL CHECK ( id ~ '^MONDO:[0-9]{7}$' ),
    name TEXT NOT NULL,
    definition TEXT,
    obsolete BOOLEAN NOT NULL DEFAULT FALSE,
    replaced_by TEXT,
    PRIMARY KEY (version_id, id),
    CHECK (obsolete OR replaced_by IS NULL)
);

CREATE INDEX mondo_term_name_trgm ON terms.mondo_term USING gin (name gin_trgm_ops);

CREATE TABLE terms.mondo_alt_id (
    version_id UUID NOT NULL REFERENCES terms.mondo_release(version_id) ON DELETE CASCADE,
    alt_id TEXT NOT NULL CHECK ( alt_id ~ '^MONDO:[0-9]{7}$' ),
    id TEXT NOT NULL,
    PRIMARY KEY (version_id, alt_id),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE terms.mondo_parent (
    version_id UUID NOT NULL REFERENCES terms.mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    parent_id TEXT NOT NULL,
    PRIMARY KEY (version_id, id, parent_id),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.mondo_term (version_id, id)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_id)
        REFERENCES terms.mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TYPE terms.mondo_synonym_scope AS ENUM ('exact', 'broad', 'narrow', 'related');

CREATE TABLE terms.mondo_synonym (
    version_id UUID NOT NULL REFERENCES terms.mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    synonym TEXT NOT NULL,
    scope terms.mondo_synonym_scope NOT NULL,
    PRIMARY KEY (version_id, id, synonym),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TYPE terms.mondo_xref_relation AS ENUM ('exact', 'close', 'broad', 'narrow', 'xref');

CREATE TABLE terms.mondo_xref (
    version_id UUID NOT NULL REFERENCES terms.mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    target_system CITEXT NOT NULL,
    target_code TEXT NOT NULL,
    relation terms.mondo_xref_relation NOT NULL,
    PRIMARY KEY (version_id, id, target_system, target_code),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE INDEX mondo_xref_reverse ON terms.mondo_xref (version_id, target_system, target_code);


CREATE TABLE terms.orphanet_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'orphanet' CHECK (code_system = 'orphanet'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.orphanet_disorder (
    version_id UUID NOT NULL REFERENCES terms.orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]+$' ),
    name TEXT NOT NULL,
    disorder_type TEXT NOT NULL,
    definition TEXT,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.orphanet_parent (
    version_id UUID NOT NULL REFERENCES terms.orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    parent_code TEXT NOT NULL,
    PRIMARY KEY (version_id, code, parent_code),
    FOREIGN KEY (version_id, code)
        REFERENCES terms.orphanet_disorder (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_code)
        REFERENCES terms.orphanet_disorder (version_id, code)
        ON DELETE CASCADE
);

CREATE TYPE terms.orphanet_xref_relation AS ENUM ('E', 'NTBT', 'BTNT', 'NTBT/E', 'BTNT/E', 'ND');

CREATE TABLE terms.orphanet_xref (
    version_id UUID NOT NULL REFERENCES terms.orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    target_system CITEXT NOT NULL,
    target_code TEXT NOT NULL,
    relation terms.orphanet_xref_relation NOT NULL,
    PRIMARY KEY (version_id, code, target_system, target_code),
    FOREIGN KEY (version_id, code)
        REFERENCES terms.orphanet_disorder (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE terms.ncit_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'ncit' CHECK (code_system = 'ncit'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.ncit_concept (
    version_id      uuid NOT NULL REFERENCES terms.ncit_release (version_id) ON DELETE CASCADE,
    code            text NOT NULL CHECK (code ~ '^C[0-9]+$'),  -- 'C3262' (Neoplasm)
    preferred_name  text NOT NULL,
    display_name    text,
    definition      text,
    semantic_type   text,
    retired         boolean NOT NULL DEFAULT false,
    PRIMARY KEY (version_id, code)
) PARTITION BY LIST (version_id);

CREATE INDEX ncit_concept_preferred_name_trgm ON terms.ncit_concept USING gin (preferred_name gin_trgm_ops);

CREATE TABLE terms.ncit_parent (
    version_id      uuid NOT NULL REFERENCES terms.ncit_release (version_id) ON DELETE CASCADE,
    code          text NOT NULL,
    parent_code   text NOT NULL,
    PRIMARY KEY (version_id, code, parent_code),
    FOREIGN KEY (version_id, code)        REFERENCES terms.ncit_concept (version_id, code) ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_code) REFERENCES terms.ncit_concept (version_id, code) ON DELETE CASCADE
);

CREATE TABLE terms.ncit_closure (
    version_id    uuid NOT NULL REFERENCES terms.ncit_release (version_id) ON DELETE CASCADE,
    ancestor_id   text NOT NULL,
    descendant_id text NOT NULL,
    depth         smallint NOT NULL,
    PRIMARY KEY (version_id, ancestor_id, descendant_id)
);

CREATE INDEX ncit_closure_up ON terms.ncit_closure (version_id, descendant_id);

CREATE TABLE terms.ncit_synonym (
    version_id      uuid NOT NULL REFERENCES terms.ncit_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL,
    term         text NOT NULL,
    term_type    text NOT NULL,
    source       text NOT NULL,
    seq          integer NOT NULL,
    PRIMARY KEY (version_id, code, seq),
    FOREIGN KEY (version_id, code) REFERENCES terms.ncit_concept (version_id, code) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX ncit_synonym_term_trgm ON terms.ncit_synonym USING gin (term gin_trgm_ops);

CREATE TABLE terms.ncit_subset_member (
    version_id      uuid NOT NULL REFERENCES terms.ncit_release (version_id) ON DELETE CASCADE,
    subset_code   text NOT NULL,
    code          text NOT NULL,
    PRIMARY KEY (version_id, subset_code, code),
    FOREIGN KEY (version_id, subset_code)
        REFERENCES terms.ncit_concept (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, code)
        REFERENCES terms.ncit_concept (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE terms.pdq_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'pdq' CHECK (code_system = 'pdq'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.pdq_term (
    version_id    uuid NOT NULL REFERENCES terms.pdq_release (version_id) ON DELETE CASCADE,
    cdr_id        text NOT NULL,
    name          text NOT NULL,
    term_type     text,
    ncit_code     text,
    PRIMARY KEY (version_id, cdr_id)
);

CREATE TABLE terms.pdq_synonym (
    version_id    uuid NOT NULL REFERENCES terms.pdq_release (version_id) ON DELETE CASCADE,
    cdr_id       text NOT NULL,
    synonym      text NOT NULL,
    PRIMARY KEY (version_id, cdr_id, synonym),
    FOREIGN KEY (version_id, cdr_id) REFERENCES terms.pdq_term (version_id, cdr_id) ON DELETE CASCADE
);