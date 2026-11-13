CREATE TABLE terms.ccsr_dx_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ccsr_dx' CHECK (code_system = 'ccsr_dx'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.ccsr_dx_category (
    version_id UUID NOT NULL REFERENCES terms.ccsr_dx_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[A-Z]{3}[0-9]{3}$' ),
    description TEXT NOT NULL,
    body_system TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.ccsr_dx_assignment (
    version_id UUID NOT NULL REFERENCES terms.ccsr_dx_release(version_id) ON DELETE CASCADE,
    dx_code TEXT NOT NULL,
    category_code TEXT NOT NULL,
    PRIMARY KEY (version_id, dx_code, category_code),
    FOREIGN KEY (version_id, category_code) REFERENCES terms.ccsr_dx_category(version_id, code) ON DELETE CASCADE
);

CREATE INDEX ccsr_dx_assignment_by_category ON terms.ccsr_dx_assignment (version_id, category_code);

CREATE TYPE terms.ccsr_setting AS ENUM ('inpatient', 'outpatient');

-- TODO(verify): check whether the CCSR default IP/OP columns contain placeholder categories
-- (e.g. XXX000, XXX111). category_code has no FK so that such values can load either way.
CREATE TABLE terms.ccsr_dx_default (
    version_id uuid NOT NULL REFERENCES terms.ccsr_dx_release ON DELETE CASCADE,
    dx_code text NOT NULL,
    setting terms.ccsr_setting NOT NULL,
    category_code text NOT NULL,  -- no FK: may be a placeholder
    PRIMARY KEY (version_id, dx_code, setting)
);

CREATE TABLE terms.ccsr_proc_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ccsr_pr' CHECK (code_system = 'ccsr_pr'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.ccsr_proc_category (
    version_id UUID NOT NULL REFERENCES terms.ccsr_proc_release(version_id) ON DELETE CASCADE,
    code TEXT NOT NULL CHECK ( code ~ '^[A-Z]{3}[0-9]{3}$' ),
    description TEXT NOT NULL,
    clinical_domain TEXT NOT NULL,
    PRIMARY KEY (version_id, code)
);

CREATE TABLE terms.ccsr_proc_assignment (
    version_id UUID NOT NULL REFERENCES terms.ccsr_proc_release(version_id) ON DELETE CASCADE,
    pcs_code TEXT NOT NULL,
    category_code TEXT NOT NULL,
    PRIMARY KEY (version_id, pcs_code),  -- TODO(verify): one category per PCS code
    FOREIGN KEY (version_id, category_code) REFERENCES terms.ccsr_proc_category(version_id, code) ON DELETE CASCADE
);

CREATE INDEX ccsr_pr_assignment_by_category ON terms.ccsr_proc_assignment (version_id, category_code);

CREATE TABLE terms.ccs_release (
    version_id   UUID PRIMARY KEY,
    code_system  CITEXT NOT NULL DEFAULT 'ccs' CHECK (code_system = 'ccs'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version(id, code_system_id) ON DELETE CASCADE
);

CREATE TYPE terms.ccs_type AS ENUM ('dx', 'pr');
CREATE TYPE terms.ccs_scheme AS ENUM ('single', 'multi');

CREATE TABLE terms.ccs_category (
    version_id UUID NOT NULL REFERENCES terms.ccs_release(version_id) ON DELETE CASCADE,
    kind terms.ccs_type NOT NULL,
    code TEXT NOT NULL,
    scheme terms.ccs_scheme NOT NULL,
    label TEXT NOT NULL,
    parent_code TEXT,
    PRIMARY KEY (version_id, kind, scheme, code),
    FOREIGN KEY (version_id, kind, scheme, parent_code)
        REFERENCES terms.ccs_category (version_id, kind, scheme, code)
        ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE terms.ccs_icd9_assignment (
    version_id UUID NOT NULL REFERENCES terms.ccs_release(version_id) ON DELETE CASCADE,
    kind terms.ccs_type NOT NULL,
    scheme terms.ccs_scheme NOT NULL,
    icd_code TEXT NOT NULL,
    category_code TEXT NOT NULL,
    PRIMARY KEY (version_id, kind, scheme, icd_code, category_code),
    FOREIGN KEY (version_id, kind, scheme, category_code)
        REFERENCES terms.ccs_category (version_id, kind, scheme, code)
        ON DELETE CASCADE
);