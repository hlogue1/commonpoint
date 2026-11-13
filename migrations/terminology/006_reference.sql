CREATE TABLE cvx_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cvx' CHECK (code_system = 'cvx'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- CDC publishes these as display strings ('Active', 'Never Active', 'Non-US', ...), sometimes
-- with stray whitespace. The loader must trim and map them to these values.
CREATE TYPE cvx_status AS ENUM ('active', 'inactive', 'never_active', 'non_us', 'pending');

CREATE TABLE cvx_vaccine (
    version_id UUID NOT NULL REFERENCES cvx_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    short_desc TEXT NOT NULL,
    full_name TEXT NOT NULL,
    status cvx_status NOT NULL,
    non_vaccine BOOLEAN NOT NULL DEFAULT FALSE,
    last_updated DATE,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE mvx_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'mvx' CHECK (code_system = 'mvx'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE mvx_manufacturer (
    version_id UUID NOT NULL REFERENCES mvx_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    name TEXT NOT NULL,
    active BOOLEAN NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE cvx_product (
    version_id UUID NOT NULL REFERENCES cvx_release(version_id) ON DELETE CASCADE,
    product_name TEXT NOT NULL,
    cvx_code TEXT NOT NULL,
    mvx_code TEXT NOT NULL,
    active BOOLEAN NOT NULL,
    PRIMARY KEY (version_id, cvx_code, mvx_code, product_name),
    FOREIGN KEY (version_id, cvx_code) REFERENCES cvx_vaccine(version_id, code) ON DELETE CASCADE
);

CREATE INDEX cvx_product_by_mvx ON cvx_product (version_id, mvx_code);

CREATE TABLE nucc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'nucc' CHECK (code_system = 'nucc'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE nucc_taxonomy (
    version_id UUID NOT NULL REFERENCES nucc_release(version_id) ON DELETE CASCADE,
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

CREATE TABLE cdc_race_ethnicity_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'cdc_race_ethnicity' CHECK (code_system = 'cdc_race_ethnicity'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE cdc_race_ethnicity_type AS ENUM ('race', 'ethnicity');

CREATE TABLE cdc_race_ethnicity_code (
    version_id UUID NOT NULL REFERENCES cdc_race_ethnicity_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK (code ~ '^[0-9]{4}-[0-9]$'),
    display TEXT NOT NULL,
    category cdc_race_ethnicity_type NOT NULL,
    hierarchical_code TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, code),
    UNIQUE (version_id, hierarchical_code),
    FOREIGN KEY (version_id, parent_code) REFERENCES cdc_race_ethnicity_code(version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE ucum_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ucum' CHECK (code_system = 'ucum'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version(id, code_system_id) ON DELETE CASCADE
);

-- A pick list of common units only. Validating an arbitrary UCUM expression needs a UCUM library.
CREATE TABLE ucum_common_unit (
    version_id UUID NOT NULL REFERENCES ucum_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL,
    display TEXT NOT NULL,
    property TEXT,
    PRIMARY KEY (version_id, code)
);


---- create above / drop below ----


DROP TABLE ucum_common_unit;
DROP TABLE ucum_release;
DROP TABLE cdc_race_ethnicity_code;
DROP TYPE cdc_race_ethnicity_type;
DROP TABLE cdc_race_ethnicity_release;
DROP TABLE nucc_taxonomy;
DROP TABLE nucc_release;
DROP TABLE cvx_product;
DROP TABLE mvx_manufacturer;
DROP TABLE mvx_release;
DROP TABLE cvx_vaccine;
DROP TYPE cvx_status;
DROP TABLE cvx_release;
