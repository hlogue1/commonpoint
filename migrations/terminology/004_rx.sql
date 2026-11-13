CREATE TABLE rxnorm_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'rxnorm' CHECK (code_system = 'rxnorm'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE rxnorm_tty (
    tty         TEXT PRIMARY KEY,
    description TEXT NOT NULL,
    is_concept  BOOLEAN NOT NULL
);

INSERT INTO rxnorm_tty (tty, description, is_concept) VALUES
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

CREATE TABLE rxnorm_concept (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL CHECK (rxcui ~ '^[0-9]+$'),
    tty TEXT NOT NULL REFERENCES rxnorm_tty (tty),
    name TEXT NOT NULL,
    prescribable BOOLEAN NOT NULL DEFAULT FALSE,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (version_id, rxcui)
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_concept_tty       ON rxnorm_concept (version_id, tty);
CREATE INDEX rxn_concept_name_trgm ON rxnorm_concept USING gin (name gin_trgm_ops);

-- Every SAB=RXNORM atom from RXNCONSO, one row per RXAUI: the concept's own name plus the
-- PSN, SY, TMSY and ET atoms that rxnorm_concept.name cannot hold. rxnorm_concept.name stays
-- the primary display. Prescribable name: tty = 'PSN'; Tall Man form: tty = 'TMSY'.
CREATE TABLE rxnorm_concept_name (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    rxaui TEXT NOT NULL CHECK (rxaui ~ '^[0-9]+$'),
    rxcui TEXT NOT NULL,
    tty TEXT NOT NULL REFERENCES rxnorm_tty (tty),
    name TEXT NOT NULL,
    suppress CHAR(1) NOT NULL DEFAULT 'N' CHECK (suppress IN ('N', 'O', 'Y', 'E')),
    PRIMARY KEY (version_id, rxaui),
    FOREIGN KEY (version_id, rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_concept_name_by_rxcui ON rxnorm_concept_name (version_id, rxcui, tty);
CREATE INDEX rxn_concept_name_trgm     ON rxnorm_concept_name USING gin (name gin_trgm_ops);

CREATE TABLE rxnorm_drug (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL,
    dose_form_rxcui TEXT,
    brand_name_rxcui TEXT,
    generic_rxcui TEXT,
    PRIMARY KEY (version_id, rxcui),
    FOREIGN KEY (version_id, rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, dose_form_rxcui) REFERENCES rxnorm_concept(version_id, rxcui),
    FOREIGN KEY (version_id, brand_name_rxcui) REFERENCES rxnorm_concept(version_id, rxcui),
    FOREIGN KEY (version_id, generic_rxcui) REFERENCES rxnorm_concept(version_id, rxcui)
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_drug_generic ON rxnorm_drug (version_id, generic_rxcui);

CREATE TABLE rxnorm_pack_member (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    pack_rxcui TEXT NOT NULL,
    component_rxcui TEXT NOT NULL,
    PRIMARY KEY (version_id, pack_rxcui, component_rxcui),
    FOREIGN KEY (version_id, pack_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, component_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

-- Holds SCD/SBD ingredients only. Pack contents are in rxnorm_pack_member.
CREATE TABLE rxnorm_drug_ingredient (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    drug_rxcui TEXT NOT NULL,
    ingredient_rxcui TEXT NOT NULL,
    precise_ingredient_rxcui TEXT,
    scdc_rxcui TEXT NOT NULL,
    strength_num_value NUMERIC,
    strength_num_unit TEXT,
    strength_denom_value NUMERIC,
    strength_denom_unit TEXT,
    PRIMARY KEY (version_id, drug_rxcui, ingredient_rxcui),
    FOREIGN KEY (version_id, drug_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, ingredient_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, precise_ingredient_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE,
    FOREIGN KEY (version_id, scdc_rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_drug_ingredient_by_ingredient ON rxnorm_drug_ingredient (version_id, ingredient_rxcui);

CREATE TABLE rxnorm_ndc (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    ndc11 TEXT NOT NULL CHECK ( ndc11 ~ '^[0-9]{11}$' ),
    rxcui TEXT NOT NULL,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (version_id, ndc11, rxcui),
    FOREIGN KEY (version_id, rxcui) REFERENCES rxnorm_concept(version_id, rxcui) ON DELETE CASCADE
) PARTITION BY LIST (version_id);

CREATE INDEX rxn_ndc_by_rxcui ON rxnorm_ndc (version_id, rxcui);

CREATE TABLE rxnorm_history (
    version_id UUID NOT NULL REFERENCES rxnorm_release(version_id) ON DELETE CASCADE,
    retired_rxcui TEXT NOT NULL,
    new_rxcui TEXT,
    UNIQUE NULLS NOT DISTINCT (version_id, retired_rxcui, new_rxcui)
) PARTITION BY LIST (version_id);

CREATE TABLE medrt_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'medrt' CHECK (code_system = 'medrt'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- TODO(verify): check the medrt_concept_kind values against a real MED-RT release;
-- 'Dose Form' and 'Therapeutic Category' are uncertain.
CREATE TYPE medrt_concept_kind AS ENUM ('EPC', 'MoA', 'PE', 'Chem/Ingredient', 'Disease/Finding', 'PK', 'Dose Form', 'Therapeutic Category');

CREATE TABLE medrt_concept (
    version_id UUID NOT NULL REFERENCES medrt_release(version_id) ON DELETE CASCADE,
    nui TEXT NOT NULL,
    name TEXT NOT NULL,
    kind medrt_concept_kind NOT NULL,
    PRIMARY KEY (version_id, nui)
);

CREATE TABLE medrt_concept_parent (
    version_id UUID NOT NULL REFERENCES medrt_release(version_id) ON DELETE CASCADE,
    nui TEXT NOT NULL,
    parent_nui TEXT NOT NULL,
    PRIMARY KEY (version_id, nui, parent_nui),
    FOREIGN KEY (version_id, nui) REFERENCES medrt_concept(version_id, nui) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (version_id, parent_nui) REFERENCES medrt_concept(version_id, nui) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TYPE medrt_rxn_link_rel AS ENUM ('has_epc', 'has_moa', 'has_pe', 'has_pk', 'may_treat', 'may_prevent', 'may_diagnose', 'ci_with', 'ci_moa', 'ci_pe', 'ci_chemclass');

CREATE TABLE medrt_rxnorm_link (
    version_id UUID NOT NULL REFERENCES medrt_release(version_id) ON DELETE CASCADE,
    ingredient_rxcui TEXT NOT NULL,
    relationship medrt_rxn_link_rel NOT NULL,
    nui TEXT NOT NULL,
    source TEXT NOT NULL,
    PRIMARY KEY (version_id, ingredient_rxcui, relationship, nui, source),
    FOREIGN KEY (version_id, nui) REFERENCES medrt_concept(version_id, nui) ON DELETE CASCADE
);

CREATE INDEX medrt_rxnorm_link_by_class ON medrt_rxnorm_link (version_id, nui, relationship);

CREATE TABLE atc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'atc' CHECK (code_system = 'atc'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE atc_code (
    version_id UUID NOT NULL REFERENCES atc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[A-Z]([0-9]{2}([A-Z]([A-Z]([0-9]{2})?)?)?)?$'),
    level SMALLINT GENERATED ALWAYS AS (CASE length(code) WHEN 1 THEN 1 WHEN 3 THEN 2 WHEN 4 THEN 3 WHEN 5 THEN 4 WHEN 7 THEN 5 END) STORED,
    name TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES atc_code(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE atc_ddd (
    version_id UUID NOT NULL REFERENCES atc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    route TEXT NOT NULL,
    ddd NUMERIC NOT NULL,
    unit TEXT NOT NULL,
    note TEXT,
    seq SMALLINT NOT NULL DEFAULT 1,
    PRIMARY KEY (version_id, code, route, seq),
    FOREIGN KEY (version_id, code) REFERENCES atc_code (version_id, code) ON DELETE CASCADE
);

CREATE TABLE atc_rxnorm_link (
    version_id UUID NOT NULL REFERENCES atc_release(version_id) ON DELETE CASCADE,
    ingredient_rxcui TEXT NOT NULL,
    atc_code TEXT NOT NULL,
    PRIMARY KEY (version_id, ingredient_rxcui, atc_code),
    FOREIGN KEY (version_id, atc_code) REFERENCES atc_code (version_id, code) ON DELETE CASCADE
);

CREATE INDEX rxn_atc_link_by_atc ON atc_rxnorm_link (version_id, atc_code);

CREATE TABLE cms_frf_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cms_frf' CHECK (code_system = 'cms_frf'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE cms_frf_drug (
    version_id UUID NOT NULL REFERENCES cms_frf_release(version_id) ON DELETE CASCADE,
    rxcui TEXT NOT NULL,
    tty TEXT REFERENCES rxnorm_tty (tty),
    name TEXT NOT NULL,
    PRIMARY KEY (version_id, rxcui)
);

CREATE TABLE uspmg_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'uspmg' CHECK (code_system = 'uspmg'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE uspmg_level AS ENUM ('category', 'class');

CREATE TABLE uspmg_class (
    version_id UUID NOT NULL REFERENCES uspmg_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    level uspmg_level NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES uspmg_class(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE uspmg_rxnorm_link (
    version_id UUID NOT NULL REFERENCES uspmg_release(version_id) ON DELETE CASCADE,
    class_code TEXT NOT NULL,
    rxcui TEXT NOT NULL,
    PRIMARY KEY (version_id, class_code, rxcui),
    FOREIGN KEY (version_id, class_code) REFERENCES uspmg_class(version_id, code) ON DELETE CASCADE
);

CREATE INDEX uspmg_rxnorm_link_by_rxcui ON uspmg_rxnorm_link (version_id, rxcui);