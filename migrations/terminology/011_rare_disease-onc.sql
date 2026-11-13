CREATE TABLE mondo_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'mondo' CHECK (code_system = 'mondo'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE mondo_term (
    version_id UUID NOT NULL REFERENCES mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL CHECK ( id ~ '^MONDO:[0-9]{7}$' ),
    name TEXT NOT NULL,
    definition TEXT,
    obsolete BOOLEAN NOT NULL DEFAULT FALSE,
    replaced_by TEXT,
    PRIMARY KEY (version_id, id),
    CHECK (obsolete OR replaced_by IS NULL)
);

CREATE INDEX mondo_term_name_trgm ON mondo_term USING gin (name gin_trgm_ops);

CREATE TABLE mondo_alt_id (
    version_id UUID NOT NULL REFERENCES mondo_release(version_id) ON DELETE CASCADE,
    alt_id TEXT NOT NULL CHECK ( alt_id ~ '^MONDO:[0-9]{7}$' ),
    id TEXT NOT NULL,
    PRIMARY KEY (version_id, alt_id),
    FOREIGN KEY (version_id, id)
        REFERENCES mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE mondo_parent (
    version_id UUID NOT NULL REFERENCES mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    parent_id TEXT NOT NULL,
    PRIMARY KEY (version_id, id, parent_id),
    FOREIGN KEY (version_id, id)
        REFERENCES mondo_term (version_id, id)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_id)
        REFERENCES mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TYPE mondo_synonym_scope AS ENUM ('exact', 'broad', 'narrow', 'related');

CREATE TABLE mondo_synonym (
    version_id UUID NOT NULL REFERENCES mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    synonym TEXT NOT NULL,
    scope mondo_synonym_scope NOT NULL,
    PRIMARY KEY (version_id, id, synonym),
    FOREIGN KEY (version_id, id)
        REFERENCES mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TYPE mondo_xref_relation AS ENUM ('exact', 'close', 'broad', 'narrow', 'xref');

CREATE TABLE mondo_xref (
    version_id UUID NOT NULL REFERENCES mondo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    target_system CITEXT NOT NULL,
    target_code TEXT NOT NULL,
    relation mondo_xref_relation NOT NULL,
    PRIMARY KEY (version_id, id, target_system, target_code),
    FOREIGN KEY (version_id, id)
        REFERENCES mondo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE INDEX mondo_xref_reverse ON mondo_xref (version_id, target_system, target_code);


CREATE TABLE orphanet_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'orphanet' CHECK (code_system = 'orphanet'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE orphanet_disorder (
    version_id UUID NOT NULL REFERENCES orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[0-9]+$' ),
    name TEXT NOT NULL,
    disorder_type TEXT NOT NULL,
    definition TEXT,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE orphanet_parent (
    version_id UUID NOT NULL REFERENCES orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    parent_code TEXT NOT NULL,
    PRIMARY KEY (version_id, code, parent_code),
    FOREIGN KEY (version_id, code)
        REFERENCES orphanet_disorder (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_code)
        REFERENCES orphanet_disorder (version_id, code)
        ON DELETE CASCADE
);

CREATE TYPE orphanet_xref_relation AS ENUM ('E', 'NTBT', 'BTNT', 'NTBT/E', 'BTNT/E', 'ND');

CREATE TABLE orphanet_xref (
    version_id UUID NOT NULL REFERENCES orphanet_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    target_system CITEXT NOT NULL,
    target_code TEXT NOT NULL,
    relation orphanet_xref_relation NOT NULL,
    PRIMARY KEY (version_id, code, target_system, target_code),
    FOREIGN KEY (version_id, code)
        REFERENCES orphanet_disorder (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE ncit_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'ncit' CHECK (code_system = 'ncit'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE ncit_concept (
    version_id      uuid NOT NULL REFERENCES ncit_release (version_id) ON DELETE CASCADE,
    code            text NOT NULL CHECK (code ~ '^C[0-9]+$'),  -- 'C3262' (Neoplasm)
    preferred_name  text NOT NULL,
    display_name    text,
    definition      text,
    semantic_type   text,
    retired         boolean NOT NULL DEFAULT false,
    PRIMARY KEY (version_id, code)
) PARTITION BY LIST (version_id);

CREATE INDEX ncit_concept_preferred_name_trgm ON ncit_concept USING gin (preferred_name gin_trgm_ops);

CREATE TABLE ncit_parent (
    version_id      uuid NOT NULL REFERENCES ncit_release (version_id) ON DELETE CASCADE,
    code          text NOT NULL,
    parent_code   text NOT NULL,
    PRIMARY KEY (version_id, code, parent_code),
    FOREIGN KEY (version_id, code)        REFERENCES ncit_concept (version_id, code) ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_code) REFERENCES ncit_concept (version_id, code) ON DELETE CASCADE
);

CREATE TABLE ncit_closure (
    version_id    uuid NOT NULL REFERENCES ncit_release (version_id) ON DELETE CASCADE,
    ancestor_id   text NOT NULL,
    descendant_id text NOT NULL,
    depth         smallint NOT NULL,
    PRIMARY KEY (version_id, ancestor_id, descendant_id)
);

CREATE INDEX ncit_closure_up ON ncit_closure (version_id, descendant_id);

CREATE TABLE ncit_synonym (
    version_id      uuid NOT NULL REFERENCES ncit_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL,
    term         text NOT NULL,
    term_type    text NOT NULL,
    source       text NOT NULL,
    seq          integer NOT NULL,
    PRIMARY KEY (version_id, code, seq),
    FOREIGN KEY (version_id, code) REFERENCES ncit_concept (version_id, code) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX ncit_synonym_term_trgm ON ncit_synonym USING gin (term gin_trgm_ops);

CREATE TABLE ncit_subset_member (
    version_id      uuid NOT NULL REFERENCES ncit_release (version_id) ON DELETE CASCADE,
    subset_code   text NOT NULL,
    code          text NOT NULL,
    PRIMARY KEY (version_id, subset_code, code),
    FOREIGN KEY (version_id, subset_code)
        REFERENCES ncit_concept (version_id, code)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, code)
        REFERENCES ncit_concept (version_id, code)
        ON DELETE CASCADE
);


CREATE TABLE pdq_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'pdq' CHECK (code_system = 'pdq'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE pdq_term (
    version_id    uuid NOT NULL REFERENCES pdq_release (version_id) ON DELETE CASCADE,
    cdr_id        text NOT NULL,
    name          text NOT NULL,
    term_type     text,
    ncit_code     text,
    PRIMARY KEY (version_id, cdr_id)
);

CREATE TABLE pdq_synonym (
    version_id    uuid NOT NULL REFERENCES pdq_release (version_id) ON DELETE CASCADE,
    cdr_id       text NOT NULL,
    synonym      text NOT NULL,
    PRIMARY KEY (version_id, cdr_id, synonym),
    FOREIGN KEY (version_id, cdr_id) REFERENCES pdq_term (version_id, cdr_id) ON DELETE CASCADE
);