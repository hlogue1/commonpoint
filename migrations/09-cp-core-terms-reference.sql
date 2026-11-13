CREATE TABLE terms.cvx_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cvx' CHECK (code_system = 'cvx'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- CDC publishes these as display strings ('Active', 'Never Active', 'Non-US', ...), sometimes
-- with stray whitespace. The loader must trim and map them to these values.
CREATE TYPE terms.cvx_status AS ENUM ('active', 'inactive', 'never_active', 'non_us', 'pending');

CREATE TABLE terms.cvx_vaccine (
    version_id UUID NOT NULL REFERENCES terms.cvx_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    short_desc TEXT NOT NULL,
    full_name TEXT NOT NULL,
    status terms.cvx_status NOT NULL,
    non_vaccine BOOLEAN NOT NULL DEFAULT FALSE,
    last_updated DATE,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.mvx_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'mvx' CHECK (code_system = 'mvx'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.mvx_manufacturer (
    version_id UUID NOT NULL REFERENCES terms.mvx_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    active BOOLEAN NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.cvx_product (
    version_id UUID NOT NULL REFERENCES terms.cvx_release(version_id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    cvx_code TEXT NOT NULL,
    mvx_code TEXT NOT NULL,
    active BOOLEAN NOT NULL,
    PRIMARY KEY (version_id, cvx_code, mvx_code, product_name),
    FOREIGN KEY (version_id, cvx_code) REFERENCES terms.cvx_vaccine(version_id, code) ON DELETE CASCADE
);

CREATE INDEX cvx_product_by_mvx ON terms.cvx_product (version_id, mvx_code);

CREATE TABLE terms.nucc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'nucc' CHECK (code_system = 'nucc'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.nucc_taxonomy (
    version_id UUID NOT NULL REFERENCES terms.nucc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( length(code) = 10 ),
    grouping TEXT NOT NULL,
    classification TEXT NOT NULL,
    specialization TEXT,
    display_name TEXT,
    definition TEXT,
    section TEXT,
    notes TEXT,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.cdc_race_ethnicity_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cdc_race_ethnicity' CHECK (code_system = 'cdc_race_ethnicity'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE terms.cdc_race_ethnicity_type AS ENUM ('race', 'ethnicity');

CREATE TABLE terms.cdc_race_ethnicity_code (
    version_id UUID NOT NULL REFERENCES terms.cdc_race_ethnicity_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9]{4}-[0-9]$'),
    display TEXT NOT NULL,
    category terms.cdc_race_ethnicity_type NOT NULL,
    hierarchical_code TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    UNIQUE (version_id, hierarchical_code),
    FOREIGN KEY (version_id, parent_code) REFERENCES terms.cdc_race_ethnicity_code(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE terms.ucum_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ucum' CHECK (code_system = 'ucum'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- A pick list of common units only. Validating an arbitrary UCUM expression needs a UCUM library.
CREATE TABLE terms.ucum_common_unit (
    version_id UUID NOT NULL REFERENCES terms.ucum_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    display TEXT NOT NULL,
    property TEXT,
    PRIMARY KEY (version_id, code)
);