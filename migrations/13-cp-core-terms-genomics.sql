CREATE TABLE terms.hgnc_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'hgnc' CHECK (code_system = 'hgnc'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TYPE terms.hgnc_gene_status AS ENUM ('approved', 'withdrawn');

CREATE TABLE terms.hgnc_gene (
    version_id UUID NOT NULL REFERENCES terms.hgnc_release(version_id) ON DELETE CASCADE,
    hgnc_id TEXT NOT NULL CHECK ( hgnc_id ~ '^HGNC:[0-9]+$' ),
    symbol TEXT NOT NULL,
    name TEXT NOT NULL,
    locus_group TEXT NOT NULL,
    locus_type TEXT NOT NULL,
    status terms.hgnc_gene_status NOT NULL,
    location TEXT,
    entrez_id TEXT,
    ensembl_gene_id TEXT,
    PRIMARY KEY (version_id, hgnc_id)
);

CREATE INDEX hgnc_gene_symbol ON terms.hgnc_gene (version_id, symbol);

CREATE TYPE terms.hgnc_alias_type AS ENUM ('alias', 'previous');

CREATE TABLE terms.hgnc_symbol_alias (
    version_id UUID NOT NULL REFERENCES terms.hgnc_release(version_id) ON DELETE CASCADE,
    hgnc_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    kind terms.hgnc_alias_type NOT NULL,
    PRIMARY KEY (version_id, hgnc_id, symbol, kind),
    FOREIGN KEY (version_id, hgnc_id)
        REFERENCES terms.hgnc_gene (version_id, hgnc_id)
        ON DELETE CASCADE
);

CREATE INDEX hgnc_symbol_alias_symbol ON terms.hgnc_symbol_alias (version_id, symbol);

CREATE TABLE terms.hgnc_withdrawn (
    version_id UUID NOT NULL REFERENCES terms.hgnc_release(version_id) ON DELETE CASCADE,
    hgnc_id TEXT NOT NULL,
    symbol TEXT NOT NULL,
    status TEXT NOT NULL,
    merged_into_id TEXT,
    UNIQUE NULLS NOT DISTINCT (version_id, hgnc_id, merged_into_id)
);


CREATE TABLE terms.hpo_release (
    version_id  UUID PRIMARY KEY,
    code_system CITEXT NOT NULL DEFAULT 'hpo' CHECK (code_system = 'hpo'),
    FOREIGN KEY (version_id, code_system)
        REFERENCES terms.code_system_version (id, code_system_id)
        ON DELETE CASCADE
);

CREATE TABLE terms.hpo_term (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL CHECK ( id ~ '^HP:[0-9]{7}$' ),
    name TEXT NOT NULL,
    definition TEXT,
    obsolete BOOLEAN NOT NULL DEFAULT FALSE,
    replaced_by TEXT,
    PRIMARY KEY (version_id, id),
    CHECK (obsolete OR replaced_by IS NULL)
);

CREATE INDEX hpo_term_name_trgm ON terms.hpo_term USING gin (name gin_trgm_ops);

CREATE TABLE terms.hpo_alt_id (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    alt_id TEXT NOT NULL CHECK ( alt_id ~ '^HP:[0-9]{7}$' ),
    id TEXT NOT NULL,
    PRIMARY KEY (version_id, alt_id),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE terms.hpo_consider (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    obsolete_id TEXT NOT NULL,
    consider_id TEXT NOT NULL,
    PRIMARY KEY (version_id, obsolete_id, consider_id)
);

CREATE TABLE terms.hpo_parent (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    parent_id TEXT NOT NULL,
    PRIMARY KEY (version_id, id, parent_id),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE,
    FOREIGN KEY (version_id, parent_id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE terms.hpo_closure (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    ancestor_id TEXT NOT NULL,
    descendant_id TEXT NOT NULL,
    depth SMALLINT NOT NULL,
    PRIMARY KEY (version_id, ancestor_id, descendant_id),
    FOREIGN KEY (version_id, ancestor_id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE ,
    FOREIGN KEY (version_id, descendant_id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE INDEX hpo_closure_up ON terms.hpo_closure (version_id, descendant_id);

CREATE TYPE terms.hpo_synonym_scope AS ENUM ('exact', 'broad', 'narrow', 'related');

CREATE TABLE terms.hpo_synonym (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    synonym TEXT NOT NULL,
    scope terms.hpo_synonym_scope NOT NULL,
    PRIMARY KEY (version_id, id, synonym),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE TABLE terms.hpo_xref (
    version_id UUID NOT NULL REFERENCES terms.hpo_release(version_id) ON DELETE CASCADE,
    id TEXT NOT NULL,
    target_system CITEXT NOT NULL,
    target_code TEXT NOT NULL,
    PRIMARY KEY (version_id, id, target_system, target_code),
    FOREIGN KEY (version_id, id)
        REFERENCES terms.hpo_term (version_id, id)
        ON DELETE CASCADE
);

CREATE INDEX hpo_xref_reverse ON terms.hpo_xref (version_id, target_system, target_code);
