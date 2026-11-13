CREATE TABLE terms.rxnorm_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'rxnorm' CHECK (code_system = 'rxnorm'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.rxnorm_tty (
    tty         TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    is_concept  BOOLEAN NOT NULL
);

INSERT INTO terms.rxnorm_tty (tty, description, is_concept) VALUES
    ('IN',    'Ingredient', TRUE),
    ('PIN',   'Precise Ingredient', TRUE),
    ('MIN',   'Multiple Ingredients', TRUE),
    ('SCDC',  'Semantic Clinical Drug Component', TRUE),
    ('SBDC',  'Semantic Branded Drug Component', TRUE),
    ('SCDF',  'Semantic Clinical Drug Form', TRUE),
    ('SBDF',  'Semantic Branded Drug Form', TRUE),
    ('SCDG',  'Semantic Clinical Drug Group', TRUE),
    ('SBDG',  'Semantic Branded Drug Group', TRUE),
    ('SCD',   'Semantic Clinical Drug', TRUE),
    ('SBD',   'Semantic Branded Drug', TRUE),
    ('GPCK',  'Generic Pack', TRUE),
    ('BPCK',  'Brand Name Pack', TRUE),
    ('BN',    'Brand Name', TRUE),
    ('DF',    'Dose Form', TRUE),
    ('DFG',   'Dose Form Group', TRUE),
    -- verified against RxNorm Technical Documentation, Appendix 5 - Term Types
    -- (https://www.nlm.nih.gov/research/umls/rxnorm/docs/appendix5.html, last reviewed 2024-08-02)
    ('SCDFP', 'Semantic Clinical Drug Form Precise', TRUE),
    ('SCDGP', 'Semantic Clinical Drug Form Group Precise', TRUE),
    ('SBDFP', 'Semantic Branded Drug Form Precise', TRUE),
    ('PSN',   'Prescribable Name', FALSE),
    ('SY',    'Synonym', FALSE),
    ('TMSY',  'Tall Man Lettering Synonym', FALSE),
    ('ET',    'Entry Term (dose forms)', FALSE);

CREATE TABLE terms.rxnorm_concept (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL CHECK (rxcui ~ '^[0-9]+$'),
    tty TEXT NOT NULL REFERENCES terms.rxnorm_tty (tty),
    name TEXT NOT NULL,
    prescribable BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (version_id, rxcui)
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_concept_tty       ON terms.rxnorm_concept (version_id, tty);
CREATE INDEX rxn_concept_name_trgm ON terms.rxnorm_concept USING gin (name gin_trgm_ops);

CREATE TABLE terms.rxnorm_drug (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL,
    dose_form_rxcui TEXT,
    brand_name_rxcui TEXT,
    generic_rxcui TEXT,
    PRIMARY KEY (version_id, rxcui),
    FOREIGN KEY (version_id, rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, dose_form_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui),
    FOREIGN KEY (version_id, brand_name_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui),
    FOREIGN KEY (version_id, generic_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui)
);

CREATE INDEX rxn_drug_generic ON terms.rxnorm_drug (version_id, generic_rxcui);

CREATE TABLE terms.rxnorm_pack_member (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    pack_rxcui TEXT NOT NULL,
    component_rxcui TEXT NOT NULL,
    PRIMARY KEY (version_id, pack_rxcui, component_rxcui),
    FOREIGN KEY (version_id, pack_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, component_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
);

-- Holds SCD/SBD ingredients only. Pack contents are in rxnorm_pack_member.
CREATE TABLE terms.rxnorm_drug_ingredient (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    drug_rxcui TEXT NOT NULL,
    ingredient_rxcui TEXT NOT NULL,
    precise_ingredient_rxcui TEXT,
    scdc_rxcui TEXT NOT NULL,
    strength_num_value NUMERIC,
    strength_num_unit TEXT,
    strength_denom_value NUMERIC,
    strength_denom_unit TEXT,
    PRIMARY KEY (version_id, drug_rxcui, ingredient_rxcui),
    FOREIGN KEY (version_id, drug_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, ingredient_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, precise_ingredient_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, scdc_rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_drug_ingredient_by_ingredient ON terms.rxnorm_drug_ingredient (version_id, ingredient_rxcui);

CREATE TABLE terms.rxnorm_ndc (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    ndc11 TEXT NOT NULL CHECK ( ndc11 ~ '^[0-9]{11}$' ),
    rxcui TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (version_id, ndc11, rxcui),
    FOREIGN KEY (version_id, rxcui) REFERENCES terms.rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_ndc_by_rxcui ON terms.rxnorm_ndc (version_id, rxcui);

CREATE TABLE terms.rxnorm_history (
    version_id UUID NOT NULL REFERENCES terms.rxnorm_release(version_id) ON DELETE CASCADE,
    retired_rxcui TEXT NOT NULL,
    new_rxcui TEXT,
    UNIQUE NULLS NOT DISTINCT (version_id, retired_rxcui, new_rxcui)
);

CREATE TABLE terms.medrt_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'medrt' CHECK (code_system = 'medrt'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- TODO(verify): check the medrt_concept_kind values against a real MED-RT release;
-- 'Dose Form' and 'Therapeutic Category' are uncertain.
CREATE TYPE terms.medrt_concept_kind AS ENUM ('EPC', 'MoA', 'PE', 'Chem/Ingredient', 'Disease/Finding', 'PK', 'Dose Form', 'Therapeutic Category');

CREATE TABLE terms.medrt_concept (
    version_id UUID NOT NULL REFERENCES terms.medrt_release(version_id) ON DELETE CASCADE,
    nui TEXT NOT NULL,
    name TEXT NOT NULL,
    kind terms.medrt_concept_kind NOT NULL,
    PRIMARY KEY (version_id, nui)
);

CREATE TABLE terms.medrt_concept_parent (
    version_id UUID NOT NULL REFERENCES terms.medrt_release(version_id) ON DELETE CASCADE,
    nui TEXT NOT NULL,
    parent_nui TEXT NOT NULL,
    PRIMARY KEY (version_id, nui, parent_nui),
    FOREIGN KEY (version_id, nui) REFERENCES terms.medrt_concept(version_id, nui) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (version_id, parent_nui) REFERENCES terms.medrt_concept(version_id, nui) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TYPE terms.medrt_rxn_link_rel AS ENUM ('has_epc', 'has_moa', 'has_pe', 'has_pk', 'may_treat', 'may_prevent', 'may_diagnose', 'ci_with', 'ci_moa', 'ci_pe', 'ci_chemclass');

CREATE TABLE terms.medrt_rxnorm_link (
    version_id UUID NOT NULL REFERENCES terms.medrt_release(version_id) ON DELETE CASCADE,
    ingredient_rxcui TEXT NOT NULL,
    relationship terms.medrt_rxn_link_rel NOT NULL,
    nui TEXT NOT NULL,
    source TEXT NOT NULL,
    PRIMARY KEY (version_id, ingredient_rxcui, relationship, nui, source),
    FOREIGN KEY (version_id, nui) REFERENCES terms.medrt_concept(version_id, nui) ON DELETE CASCADE
);

CREATE INDEX medrt_rxnorm_link_by_class ON terms.medrt_rxnorm_link (version_id, nui, relationship);

CREATE TABLE terms.atc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'atc' CHECK (code_system = 'atc'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.atc_code (
    version_id UUID NOT NULL REFERENCES terms.atc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[A-Z]([0-9]{2}([A-Z]([A-Z]([0-9]{2})?)?)?)?$'),
    level SMALLINT GENERATED ALWAYS AS (CASE length(code) WHEN 1 THEN 1 WHEN 3 THEN 2 WHEN 4 THEN 3 WHEN 5 THEN 4 WHEN 7 THEN 5 END) STORED,
    name TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES terms.atc_code(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE terms.atc_ddd (
    version_id UUID NOT NULL REFERENCES terms.atc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    route TEXT NOT NULL,
    ddd NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    note TEXT,
    seq SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (version_id, code, route, seq),
    FOREIGN KEY (version_id, code) REFERENCES terms.atc_code (version_id, code) ON DELETE CASCADE
);

CREATE TABLE terms.atc_rxnorm_link (
    version_id UUID NOT NULL REFERENCES terms.atc_release(version_id) ON DELETE CASCADE,
    ingredient_rxcui TEXT NOT NULL,
    atc_code TEXT NOT NULL,
    PRIMARY KEY (version_id, ingredient_rxcui, atc_code),
    FOREIGN KEY (version_id, atc_code) REFERENCES terms.atc_code (version_id, code) ON DELETE CASCADE
);

CREATE INDEX rxn_atc_link_by_atc ON terms.atc_rxnorm_link (version_id, atc_code);

CREATE TABLE terms.cms_frf_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cms_frf' CHECK (code_system = 'cms_frf'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.cms_frf_drug (
    version_id UUID NOT NULL REFERENCES terms.cms_frf_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL,
    tty TEXT REFERENCES terms.rxnorm_tty (tty),
    name TEXT NOT NULL,
    PRIMARY KEY (version_id, rxcui)
);

CREATE TABLE terms.uspmg_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'uspmg' CHECK (code_system = 'uspmg'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE terms.uspmg_level AS ENUM ('category', 'class');

CREATE TABLE terms.uspmg_class (
    version_id UUID NOT NULL REFERENCES terms.uspmg_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    level terms.uspmg_level NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES terms.uspmg_class(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE terms.uspmg_rxnorm_link (
    version_id UUID NOT NULL REFERENCES terms.uspmg_release(version_id) ON DELETE CASCADE,
    class_code TEXT NOT NULL,
    rxcui TEXT NOT NULL,
    PRIMARY KEY (version_id, class_code, rxcui),
    FOREIGN KEY (version_id, class_code) REFERENCES terms.uspmg_class(version_id, code) ON DELETE CASCADE
);

CREATE INDEX uspmg_rxnorm_link_by_rxcui ON terms.uspmg_rxnorm_link (version_id, rxcui);