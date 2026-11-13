CREATE TYPE admin_sex AS ENUM ('male', 'female', 'other');
CREATE TYPE merge_confidence_level AS ENUM ('low', 'some', 'high', 'certain');

CREATE OR REPLACE FUNCTION mod97_check_digits(payload text)
    RETURNS text
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
SELECT CASE
           WHEN payload ~ '^[0-9]+$'
               THEN lpad((98 - ((payload || '00')::numeric % 97))::text, 2, '0')
           END
$$;

CREATE OR REPLACE FUNCTION mod97_is_valid(value text)
    RETURNS boolean
    LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
SELECT CASE
           WHEN value ~ '^[0-9]{3,}$' THEN value::numeric % 97 = 1
           ELSE false
           END
$$;

CREATE DOMAIN clinical_identifier AS text
    CHECK (VALUE ~ '^[0-9]{10}$' AND mod97_is_valid(VALUE));

CREATE SEQUENCE mrn_seq MINVALUE 1 MAXVALUE 99999999 NO CYCLE;

CREATE OR REPLACE FUNCTION next_mrn()
    RETURNS clinical_identifier
    LANGUAGE sql VOLATILE
AS $$
SELECT (p || mod97_check_digits(p))::clinical_identifier
FROM (SELECT lpad(nextval('mrn_seq')::text, 8, '0') AS p) s
$$;

CREATE TABLE patient_type (
    id CITEXT PRIMARY KEY NOT NULL,
    display_name TEXT,
    is_active BOOLEAN NOT NULL
);

INSERT INTO content_type VALUES ('patient_type', 'Patient Type');

CREATE TABLE patient_type_flag (
    patient_type_id CITEXT NOT NULL REFERENCES patient_type(id),
    flag_id CITEXT NOT NULL REFERENCES data_flag(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (lower(patient_type_id::text) WITH =, lower(flag_id::text) WITH =, validity WITH &&)
);

INSERT INTO content_type VALUES ('patient_type_flag', 'Patient Type Flag', ARRAY['type', 'flag']);

CREATE TABLE patient_identity_type (
    id CITEXT PRIMARY KEY NOT NULL,
    display_name TEXT,
    is_active BOOLEAN NOT NULL
);

INSERT INTO content_type VALUES ('patient_identity_type', 'Patient Identity Type');

CREATE TABLE patient_identity_type_flag (
    identity_type_id CITEXT NOT NULL REFERENCES patient_identity_type(id),
    flag_id CITEXT NOT NULL REFERENCES data_flag(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (lower(identity_type_id::text) WITH =, lower(flag_id::text) WITH =, validity WITH &&)
);

INSERT INTO content_type VALUES ('patient_identity_type_flag', 'Patient Identity Type Flag', ARRAY['type', 'flag']);

CREATE TABLE patient_identity_status_option (
    id CITEXT PRIMARY KEY NOT NULL,
    display_name TEXT,
    is_active BOOLEAN NOT NULL
);

INSERT INTO content_type VALUES ('patient_identity_status_option', 'Patient Identity Status Option');

CREATE TABLE patient_identity_status_option_flag (
    status_option_id CITEXT NOT NULL REFERENCES patient_identity_type(id),
    flag_id CITEXT NOT NULL REFERENCES data_flag(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (lower(status_option_id::text) WITH =, lower(flag_id::text) WITH =, validity WITH &&)
);

INSERT INTO content_type VALUES ('patient_identity_status_option_flag', 'Patient Identity Status Option Flag', ARRAY['status', 'flag']);

CREATE TABLE patient_external_identifier_type (
    id CITEXT PRIMARY KEY NOT NULL,
    display_name TEXT,
    is_active BOOLEAN NOT NULL
);

INSERT INTO content_type VALUES ('patient_external_identifier_type', 'Patient External Identifier Type');

CREATE TABLE patient_external_identifier_data_flag (
    type_id CITEXT NOT NULL REFERENCES patient_external_identifier_type(id),
    flag_id CITEXT NOT NULL REFERENCES data_flag(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (lower(type_id::text) WITH =, lower(flag_id::text) WITH =, validity WITH &&)
);

INSERT INTO content_type VALUES ('patient_external_identifier_data_flag', 'Patient External Identifier Type Flag', ARRAY['type', 'flag']);

CREATE TABLE patient (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_test_patient BOOLEAN NOT NULL DEFAULT FALSE,
    mrn clinical_identifier NOT NULL UNIQUE DEFAULT next_mrn(),
    admin_sex admin_sex DEFAULT NULL,
    birth_sex admin_sex DEFAULT NULL,
    birth_date timestamptz,
    is_multiple_birth BOOLEAN DEFAULT NULL,
    multiple_birth_count SMALLINT DEFAULT NULL CHECK ( multiple_birth_count ISNULL OR multiple_birth_count > 0),
    is_deceased BOOLEAN DEFAULT NULL,
    deceased_date timestamptz DEFAULT NULL,
    marital_status_id BIGINT DEFAULT NULL,
    photo_path TEXT DEFAULT NULL,
    merged_record_id UUID DEFAULT NULL REFERENCES patient(id),
    merge_confidence merge_confidence_level DEFAULT NULL,
    merge_remarks TEXT DEFAULT NULL
);

INSERT INTO content_type VALUES ('patient', 'Patient', ARRAY['type', 'is_active', 'is_test', 'is_deceased']);

CREATE TABLE patient_address (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    patient_id UUID REFERENCES patient(id) NOT NULL,
    data address NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO content_type VALUES ('patient_address', 'Patient Address', ARRAY['patient']);

CREATE TABLE patient_name (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    patient_id UUID REFERENCES patient(id) NOT NULL,
    data human_name NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO content_type VALUES ('patient_name', 'Patient Name', ARRAY['patient']);

CREATE TABLE patient_external_identifier (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    patient_id UUID NOT NULL REFERENCES patient(id),
    type_id CITEXT NOT NULL REFERENCES patient_external_identifier_type(id),
    value TEXT NOT NULL,
    is_primary BOOLEAN NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO content_type VALUES ('patient_external_identifier', 'Patient External Identifier', ARRAY['patient', 'type']);

CREATE TABLE patient_contact_point (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    patient_id UUID REFERENCES patient(id) NOT NULL,
    data contact_point NOT NULL,
    rank SMALLINT CHECK ( rank > 0 ),
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO content_type VALUES ('patient_contact_point', 'Patient Contact Point', ARRAY['patient']);

CREATE TABLE patient_identity (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    patient_id UUID NOT NULL REFERENCES patient(id),
    type_id CITEXT NOT NULL REFERENCES patient_identity_type(id),
    status_id CITEXT NOT NULL REFERENCES patient_identity_status_option(id),
    remarks TEXT DEFAULT NULL,
    timestamp timestamptz NOT NULL DEFAULT now()
);

INSERT INTO content_type VALUES ('patient_identity', 'Patient Identity', ARRAY['patient']);

CREATE TABLE patient_contact_type (
    id CITEXT PRIMARY KEY NOT NULL,
    display_name TEXT,
    is_active BOOLEAN NOT NULL
);

INSERT INTO content_type VALUES ('patient_contact_type', 'Patient Contact Type');

CREATE TABLE patient_contact_type_flag (
    type_id CITEXT NOT NULL REFERENCES patient_identity_type(id),
    flag_id CITEXT NOT NULL REFERENCES data_flag(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (lower(type_id::text) WITH =, lower(flag_id::text) WITH =, validity WITH &&)
);

INSERT INTO content_type VALUES ('patient_contact_type_flag', 'Patient Contact Type Flag', ARRAY['type', 'flag']);

CREATE TABLE patient_contact (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    type_id CITEXT NOT NULL REFERENCES patient_contact_type(id),
    patient_id UUID NOT NULL REFERENCES patient(id)
);

INSERT INTO content_type VALUES ('patient_contact', 'Patient Contact', ARRAY['patient', 'type']);

CREATE TABLE patient_contact_address (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    contact_id UUID REFERENCES patient_contact(id) NOT NULL,
    data address NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO content_type VALUES ('patient_contact_address', 'Patient Contact Address');

CREATE TABLE patient_contact_name (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    contact_id UUID REFERENCES patient_contact(id) NOT NULL,
    data human_name NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO content_type VALUES ('patient_contact_name', 'Patient Contact Address');

CREATE TABLE patient_contact_contact_point (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    contact_id UUID REFERENCES patient_contact(id) NOT NULL,
    data contact_point NOT NULL,
    rank SMALLINT CHECK ( rank > 0 ),
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO content_type VALUES ('patient_contact_contact_point', 'Patient Contact Address');