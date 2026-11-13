CREATE SCHEMA IF NOT EXISTS identity;

CREATE TYPE identity.auth_login_block AS ENUM ('inactive', 'bad_credential');

CREATE TABLE identity."user"(
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    username citext UNIQUE NOT NULL,
    login_block identity.auth_login_block,
    external_idp_id TEXT,
    employee_id TEXT,
    cost_center TEXT,
    organization TEXT,
    division TEXT,
    department TEXT,
    manager_id UUID REFERENCES identity."user"(id),
    photo_url TEXT,
    force_password_change BOOL NOT NULL DEFAULT FALSE,
    force_pin_change BOOL NOT NULL DEFAULT FALSE
);

CREATE UNIQUE INDEX ix_user_external_idp_id_key ON identity."user" (external_idp_id) WHERE external_idp_id IS NOT NULL;
CREATE UNIQUE INDEX ix_user_employee_id_key     ON identity."user" (employee_id)     WHERE employee_id IS NOT NULL;

INSERT INTO config.content_type VALUES ('user', 'User', ARRAY['id', 'role']);

CREATE TABLE identity.user_contact_point (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID REFERENCES identity."user"(id) NOT NULL,
    data config.contact_point NOT NULL,
    rank SMALLINT CHECK ( rank > 0 ),
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO config.content_type VALUES ('user_contact_point', 'User Contact Point', ARRAY['user']);

CREATE TABLE identity.user_address (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID REFERENCES identity."user"(id) NOT NULL,
    data config.address NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

INSERT INTO config.content_type VALUES ('user_address', 'User Address', ARRAY['user']);

CREATE TABLE identity.user_name (
      id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
      user_id UUID REFERENCES identity."user"(id) NOT NULL,
      data config.human_name NOT NULL,
      validity tstzrange NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('user_name', 'User Name', ARRAY['user']);

CREATE TYPE identity.auth_client_type AS ENUM ('public', 'confidential');
CREATE TYPE identity.auth_token_endpoint_method AS ENUM ('client_secret_basic', 'client_secret_post', 'private_key_jwt', 'none');
CREATE TYPE identity.auth_mtls_mode AS ENUM ('strict', 'required', 'allowed', 'unsupported');
CREATE TYPE identity.auth_grant_type AS ENUM ('authorization_code', 'client_credentials', 'refresh_token', 'device_code');
CREATE TYPE identity.oidc_response_type AS ENUM ('code', 'id_token', 'token', 'none');

CREATE TABLE identity.application (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    display_name TEXT NOT NULL,
    client_alias citext UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    type identity.auth_client_type NOT NULL,
    require_pkce BOOLEAN NOT NULL DEFAULT TRUE,
    require_par BOOLEAN NOT NULL DEFAULT TRUE,
    token_endpoint_auth_method identity.auth_token_endpoint_method NOT NULL,
    mtls_mode identity.auth_mtls_mode NOT NULL DEFAULT 'unsupported',
    id_token_ttl interval,
    access_token_ttl interval,
    refresh_token_ttl interval,
    auth_transaction_ttl interval,
    use_smart_ehr_launch BOOLEAN NOT NULL DEFAULT FALSE,
    use_smart_standalone_launch BOOLEAN NOT NULL DEFAULT FALSE,
    grant_types identity.auth_grant_type[],
    oidc_response_types identity.oidc_response_type[],
    authorized_callback_urls TEXT[],
    post_logout_redirect_urls TEXT[]
);

INSERT INTO config.content_type VALUES ('application', 'Application', ARRAY['id']);

CREATE TABLE identity.scope (
    id CITEXT PRIMARY KEY NOT NULL,
    description TEXT
);

INSERT INTO identity.scope (id, description) VALUES
    ('openid', 'OpenID Connect'),
    ('profile', 'Profile Data'),
    ('email', 'E-Mail Address'),
    ('address', 'Address'),
    ('phone', 'Phone Number'),
    ('photo', 'Photo'),
    ('offline_access', 'Offline Access');

INSERT INTO config.content_type VALUES ('scope', 'Auth Scope');

CREATE TABLE identity.application_scope (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    application_id UUID NOT NULL REFERENCES identity.application(id),
    scope_id CITEXT NOT NULL REFERENCES identity.scope(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (application_id WITH =, lower(scope_id::text) WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('application_scope', 'Allowed Application Scope', ARRAY['application', 'scope']);

CREATE TYPE identity.device_status AS ENUM ('provisioning', 'active', 'suspended', 'revoked', 'decommissioned');
CREATE TYPE identity.device_trust_level AS ENUM ('managed', 'trusted_internal', 'trusted_external');

CREATE TABLE identity.device_type (
    id CITEXT NOT NULL PRIMARY KEY,
    description TEXT
);

INSERT INTO identity.device_type (id, description) VALUES
    ('workstation', 'Workstation'),
    ('shared', 'Shared Workstation'),
    ('kiosk', 'Kiosk');

INSERT INTO config.content_type VALUES ('device_type', 'Device Type');

CREATE TABLE identity.device (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    name TEXT,
    location TEXT,
    status identity.device_status NOT NULL,
    trust identity.device_trust_level,
    type_id CITEXT NOT NULL REFERENCES identity.device_type(id)
);

INSERT INTO config.content_type VALUES ('device', 'Device', ARRAY['id', 'type', 'status', 'role']);

CREATE TABLE identity.device_downtime_region (
    device_id UUID NOT NULL REFERENCES identity.device(id),
    region_id UUID NOT NULL REFERENCES build.downtime_region(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (device_id WITH =, region_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('device_downtime_region', 'Device Downtime Region', ARRAY['device', 'region']);

CREATE TABLE config.permission (
    content_type_id CITEXT NOT NULL REFERENCES config.content_type(id),
    permission_id CITEXT NOT NULL,
    description TEXT,
    is_targeted BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (content_type_id, permission_id),
    UNIQUE (content_type_id, permission_id, is_targeted)
);

INSERT INTO config.content_type VALUES ('permission', 'Permission');

CREATE TABLE identity.role (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    display_name TEXT NOT NULL,
    is_device_class BOOLEAN NOT NULL,
    is_active BOOLEAN NOT NULL
);

INSERT INTO config.content_type VALUES ('role', 'Role', ARRAY['id']);

CREATE TABLE identity."group" (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    display_name TEXT NOT NULL,
    external_id TEXT,
    is_active BOOLEAN NOT NULL
);

CREATE UNIQUE INDEX ix_group_external_id_key    ON identity."group" (external_id)    WHERE external_id IS NOT NULL;

INSERT INTO config.content_type VALUES ('group', 'Group', ARRAY['id']);

CREATE TABLE identity.auth_policy (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    data JSONB NOT NULL
);

INSERT INTO config.content_type VALUES ('auth_policy', 'Auth Policy');

CREATE TYPE identity.auth_service_status AS ENUM ('active', 'locked', 'suspended', 'revoked');

CREATE TABLE identity.service (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    status identity.auth_service_status NOT NULL,
    display_name TEXT NOT NULL
);

INSERT INTO config.content_type VALUES ('service', 'Service', ARRAY['id', 'role']);

CREATE TABLE identity.session (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    application_id UUID NOT NULL REFERENCES identity.application(id),
    user_id UUID REFERENCES identity."user"(id),
    device_id UUID REFERENCES identity.device(id),
    token_id UUID NOT NULL UNIQUE,
    previous_token_id UUID,
    last_refresh timestamptz,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CHECK ( user_id IS NOT NULL OR device_id IS NOT NULL)
);

INSERT INTO config.content_type VALUES ('session', 'Session', ARRAY['user', 'device', 'application']);

CREATE TABLE identity.application_secret (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    application_id UUID NOT NULL REFERENCES identity.application(id),
    data TEXT NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('application_secret', 'Application Secret', ARRAY['application']);

CREATE TABLE identity.device_certificate (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    thumbprint BYTEA NOT NULL UNIQUE,
    public_key BYTEA NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('device_certificate', 'Device Certificate', ARRAY['device', 'role', 'type']);

CREATE TABLE identity.service_key (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    service_id UUID NOT NULL REFERENCES identity.service(id),
    key TEXT NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('service_key', 'Service Key', ARRAY['service']);

CREATE TABLE identity.user_recovery_code (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    hashed_code TEXT NOT NULL,
    used timestamptz,
    issued timestamptz NOT NULL DEFAULT now()
);

INSERT INTO config.content_type VALUES ('user_recovery_code', 'User Account Recovery Code', ARRAY['user']);

CREATE TABLE identity.user_webauthn (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    name TEXT NOT NULL,
    credential_id TEXT NOT NULL UNIQUE,
    public_key BYTEA NOT NULL,
    sign_in_count BIGINT CHECK ( sign_in_count >= 0 ),
    last_used TIMESTAMPTZ,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('user_webauthn', 'User Passkey (WebAuthn)', ARRAY['user']);

CREATE TABLE identity.user_password (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    hashed TEXT NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT user_password_one_active
        EXCLUDE USING gist (user_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('user_password', 'User Password', ARRAY['user']);

CREATE TABLE identity.user_physical_credential_type (
    id CITEXT PRIMARY KEY NOT NULL,
    description TEXT
);

INSERT INTO config.content_type VALUES ('user_physical_credential_type', 'User Physical Credential Type', ARRAY['user', 'type']);

CREATE TABLE identity.user_physical_credential (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    type_id CITEXT NOT NULL REFERENCES identity.user_physical_credential_type(id),
    identifier BYTEA NOT NULL,
    issuer TEXT NOT NULL,
    format_version INTEGER,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (lower(type_id::text) WITH =, identifier WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('user_physical_credential', 'User Physical Credential');

CREATE TABLE identity.user_pin (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    hashed TEXT NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT user_pin_one_active
        EXCLUDE USING gist (user_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('user_pin', 'User PIN', ARRAY['user']);

CREATE TABLE identity.user_totp_provider (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    label TEXT NOT NULL,
    key_id TEXT NOT NULL,
    secret BYTEA NOT NULL,
    code_length SMALLINT CHECK ( code_length > 0 ),
    ttl INTERVAL NOT NULL,
    alg TEXT NOT NULL,
    is_confirmed BOOLEAN NOT NULL,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('user_totp_provider', 'User TOTP Provider', ARRAY['user']);

CREATE TABLE identity.device_application (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    application_id UUID NOT NULL REFERENCES identity.application(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (device_id WITH =, application_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('device_application', 'Device Application', ARRAY['device', 'application']);

CREATE TABLE identity.device_permission (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    permission_content_type_id CITEXT NOT NULL,
    permission_id CITEXT NOT NULL,
    is_targeted BOOLEAN NOT NULL,
    target JSONB,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),

    FOREIGN KEY (permission_content_type_id, permission_id, is_targeted)
        REFERENCES config.permission(content_type_id, permission_id, is_targeted)
        ON UPDATE CASCADE,

    CHECK (is_targeted = (target IS NOT NULL)),
    CHECK (target IS NULL OR target = '"*"'::jsonb OR jsonb_typeof(target) = 'object')
);

INSERT INTO config.content_type VALUES ('device_permission', 'Device Permission');

CREATE TABLE identity.device_role (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    role_id UUID NOT NULL REFERENCES identity.role(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT device_role_no_overlap EXCLUDE USING gist (device_id WITH =, role_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('device_role', 'Device Role', ARRAY['device', 'role']);

CREATE TABLE identity.group_role (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    group_id UUID NOT NULL REFERENCES identity."group"(id),
    role_id UUID NOT NULL REFERENCES identity.role(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT group_role_no_overlap EXCLUDE USING gist (group_id WITH =, role_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('group_role', 'Group Role', ARRAY['group', 'role']);

CREATE TABLE identity.role_permission (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    role_id UUID NOT NULL REFERENCES identity.role(id),
    permission_content_type_id CITEXT NOT NULL,
    permission_id CITEXT NOT NULL,
    is_targeted BOOLEAN NOT NULL,
    target JSONB,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),

    FOREIGN KEY (permission_content_type_id, permission_id, is_targeted)
        REFERENCES config.permission(content_type_id, permission_id, is_targeted)
        ON UPDATE CASCADE,
    CHECK (is_targeted = (target IS NOT NULL)),
    CHECK (target IS NULL OR target = '"*"'::jsonb OR jsonb_typeof(target) = 'object')
);

INSERT INTO config.content_type VALUES ('role_permission', 'Role Permission');

CREATE TABLE identity.service_permission (
     id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
     service_id UUID NOT NULL REFERENCES identity.service(id),
     permission_content_type_id CITEXT NOT NULL,
     permission_id CITEXT NOT NULL,
     is_targeted BOOLEAN NOT NULL,
     target JSONB,
     validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),

     FOREIGN KEY (permission_content_type_id, permission_id, is_targeted)
         REFERENCES config.permission(content_type_id, permission_id, is_targeted)
         ON UPDATE CASCADE,
     CHECK (is_targeted = (target IS NOT NULL)),
     CHECK (target IS NULL OR target = '"*"'::jsonb OR jsonb_typeof(target) = 'object')
);

INSERT INTO config.content_type VALUES ('service_permission', 'Service Permission');

CREATE TABLE identity.user_application (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    application_id UUID NOT NULL REFERENCES identity.application(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity))
);

INSERT INTO config.content_type VALUES ('user_application', 'User Application', ARRAY['user', 'application']);

CREATE TABLE identity.user_group (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    group_id UUID NOT NULL REFERENCES identity."group"(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT user_group_no_overlap EXCLUDE USING gist (user_id WITH =, group_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('user_group', 'User Group', ARRAY['user', 'group']);

CREATE TABLE identity.device_group (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    group_id UUID NOT NULL REFERENCES identity."group"(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT device_group_no_overlap EXCLUDE USING gist (device_id WITH =, group_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('device_group', 'Device Group', ARRAY['device', 'group']);

CREATE TABLE identity.service_group (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    service_id UUID NOT NULL REFERENCES identity.service(id),
    group_id UUID NOT NULL REFERENCES identity."group"(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT service_group_no_overlap EXCLUDE USING gist (service_id WITH =, group_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('service_group', 'Service Group', ARRAY['service', 'group']);

CREATE TABLE identity.user_role (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    role_id UUID NOT NULL REFERENCES identity.role(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT user_role_no_overlap EXCLUDE USING gist (user_id WITH =, role_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('user_role', 'User Role', ARRAY['user', 'role']);

CREATE TABLE identity.service_role (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    service_id UUID NOT NULL REFERENCES identity.service(id),
    role_id UUID NOT NULL REFERENCES identity.role(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    CONSTRAINT service_role_no_overlap EXCLUDE USING gist (service_id WITH =, role_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('service_role', 'Service Role', ARRAY['service', 'role']);

CREATE TABLE identity.user_permission (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    permission_content_type_id CITEXT NOT NULL,
    permission_id CITEXT NOT NULL,
    is_targeted BOOLEAN NOT NULL,
    target JSONB,
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),

    FOREIGN KEY (permission_content_type_id, permission_id, is_targeted)
        REFERENCES config.permission(content_type_id, permission_id, is_targeted)
        ON UPDATE CASCADE,
    CHECK (is_targeted = (target IS NOT NULL)),
    CHECK (target IS NULL OR target = '"*"'::jsonb OR jsonb_typeof(target) = 'object')
);

INSERT INTO config.content_type VALUES ('user_permission', 'User Permission');

CREATE TABLE identity.device_auth_attempt (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    application_id UUID NOT NULL REFERENCES identity.application(id),
    timestamp timestamptz NOT NULL DEFAULT now(),
    is_success BOOLEAN NOT NULL
);

INSERT INTO config.content_type VALUES ('device_auth_attempt', 'Device Auth Attempt');

CREATE TABLE identity.service_auth_attempt (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    service_id UUID NOT NULL REFERENCES identity.service(id),
    application_id UUID NOT NULL REFERENCES identity.application(id),
    ip_address inet NOT NULL,
    is_success BOOLEAN NOT NULL,
    timestamp timestamptz NOT NULL DEFAULT now()
);

INSERT INTO config.content_type VALUES ('service_auth_attempt', 'Service Auth Attempt');

CREATE TABLE identity.user_auth_attempt (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    application_id UUID NOT NULL REFERENCES identity.application(id),
    device_id UUID REFERENCES identity.device(id),
    ip_address inet NOT NULL,
    is_badge BOOLEAN NOT NULL,
    is_otp BOOLEAN NOT NULL,
    is_pin BOOLEAN NOT NULL,
    is_webauthn BOOLEAN NOT NULL,
    is_password BOOLEAN NOT NULL,
    is_password_correct BOOLEAN,
    is_pin_correct BOOLEAN,
    is_success BOOLEAN NOT NULL,
    timestamp timestamptz NOT NULL DEFAULT now()
);

INSERT INTO config.content_type VALUES ('user_auth_attempt', 'User Auth Attempt');

CREATE TABLE build.idlink_device_policy (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id UUID NOT NULL REFERENCES identity.device(id),
    name CITEXT NOT NULL,
    version SMALLINT CHECK ( version > 0 ),
    description TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    data JSONB NOT NULL,
    UNIQUE (device_id, name, version)
);

INSERT INTO config.content_type VALUES ('idlink_device_policy', 'IdLink Device Policy');

CREATE TABLE identity.idlink (
    id UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id UUID NOT NULL REFERENCES identity."user"(id),
    device_id UUID NOT NULL REFERENCES identity.device(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (user_id WITH =, device_id WITH =, validity WITH &&)
);

INSERT INTO config.content_type VALUES ('idlink', 'IdLink Trust Relationship');

CREATE TABLE identity.idlink_session (
    idlink_id UUID NOT NULL REFERENCES identity.idlink(id),
    session_id UUID NOT NULL REFERENCES identity.session(id),
    validity tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    PRIMARY KEY (idlink_id, session_id)
);

INSERT INTO config.content_type VALUES ('idlink_session', 'IdLink Session Relationship');

CREATE INDEX ON identity.user_permission    (user_id);
CREATE INDEX ON identity.device_permission  (device_id);
CREATE INDEX ON identity.service_permission (service_id);
CREATE INDEX ON identity.role_permission    (role_id);
CREATE INDEX ON identity.user_permission    (permission_content_type_id, permission_id, is_targeted);
CREATE INDEX ON identity.device_permission  (permission_content_type_id, permission_id, is_targeted);
CREATE INDEX ON identity.service_permission (permission_content_type_id, permission_id, is_targeted);
CREATE INDEX ON identity.role_permission    (permission_content_type_id, permission_id, is_targeted);

CREATE INDEX ON identity.user_group    (group_id);
CREATE INDEX ON identity.device_group  (group_id);
CREATE INDEX ON identity.service_group (group_id);
CREATE INDEX ON identity.group_role    (role_id);
CREATE INDEX ON identity.user_role     (role_id);
CREATE INDEX ON identity.device_role   (role_id);
CREATE INDEX ON identity.service_role  (role_id);

CREATE INDEX ON identity.user_contact_point       (user_id);
CREATE INDEX ON identity.user_address             (user_id);
CREATE INDEX ON identity.user_name                (user_id);
CREATE INDEX ON identity.user_recovery_code       (user_id);
CREATE INDEX ON identity.user_webauthn            (user_id);
CREATE INDEX ON identity.user_totp_provider       (user_id);
CREATE INDEX ON identity.user_physical_credential (user_id);
CREATE INDEX ON identity."user"                   (manager_id);

CREATE INDEX ON identity.application_secret (application_id);
CREATE INDEX ON identity.device_certificate (device_id);
CREATE INDEX ON identity.service_key        (service_id);
CREATE INDEX ON identity.device             (type_id);
CREATE INDEX ON identity.idlink             (device_id);
CREATE INDEX ON identity.idlink_session     (session_id);

CREATE INDEX ON identity.session (user_id);
CREATE INDEX ON identity.session (device_id);
CREATE INDEX ON identity.session (application_id);

CREATE INDEX ON identity.user_auth_attempt    (user_id, timestamp DESC);
CREATE INDEX ON identity.device_auth_attempt  (device_id, timestamp DESC);
CREATE INDEX ON identity.service_auth_attempt (service_id, timestamp DESC);

CREATE VIEW identity.principal_role AS
-- direct assignments
SELECT 'user'::text AS principal_type, user_id AS principal_id,
       role_id, NULL::uuid AS via_group_id, validity
FROM identity.user_role
UNION ALL
SELECT 'device', device_id, role_id, NULL, validity
FROM identity.device_role
UNION ALL
SELECT 'service', service_id, role_id, NULL, validity
FROM identity.service_role
-- through groups
UNION ALL
SELECT 'user', ug.user_id, gr.role_id, ug.group_id, ug.validity * gr.validity
FROM identity.user_group ug
         JOIN identity.group_role gr ON gr.group_id = ug.group_id AND gr.validity && ug.validity
UNION ALL
SELECT 'device', dg.device_id, gr.role_id, dg.group_id, dg.validity * gr.validity
FROM identity.device_group dg
         JOIN identity.group_role gr ON gr.group_id = dg.group_id AND gr.validity && dg.validity
UNION ALL
SELECT 'service', sg.service_id, gr.role_id, sg.group_id, sg.validity * gr.validity
FROM identity.service_group sg
         JOIN identity.group_role gr ON gr.group_id = sg.group_id AND gr.validity && sg.validity;

CREATE VIEW identity.permission_grant AS
SELECT 'user'::text AS principal_type, user_id AS principal_id,
       permission_content_type_id, permission_id, target, validity
FROM identity.user_permission
UNION ALL
SELECT 'device', device_id, permission_content_type_id, permission_id, target, validity
FROM identity.device_permission
UNION ALL
SELECT 'service', service_id, permission_content_type_id, permission_id, target, validity
FROM identity.service_permission
UNION ALL
SELECT 'role', role_id, permission_content_type_id, permission_id, target, validity
FROM identity.role_permission;

CREATE VIEW identity.active_principal AS
SELECT 'user'::text AS principal_type, id AS principal_id
FROM identity."user"
WHERE login_block IS DISTINCT FROM 'inactive'
UNION ALL
SELECT 'device', id FROM identity.device  WHERE status = 'active'
UNION ALL
SELECT 'service', id FROM identity.service WHERE status = 'active';

CREATE VIEW identity.effective_permission AS
SELECT g.*
FROM (
         -- direct grants
         SELECT principal_type, principal_id,
                permission_content_type_id, permission_id, target, validity,
                NULL::uuid AS via_role_id, NULL::uuid AS via_group_id
         FROM identity.permission_grant
         WHERE principal_type <> 'role'
         UNION ALL
         -- grants through roles
         SELECT pr.principal_type, pr.principal_id,
                rp.permission_content_type_id, rp.permission_id, rp.target,
                pr.validity * rp.validity,
                pr.role_id, pr.via_group_id
         FROM identity.principal_role pr
                  JOIN identity.role r
                       ON r.id = pr.role_id
                           AND r.is_active
                           AND r.is_device_class = (pr.principal_type = 'device')
                  LEFT JOIN identity."group" grp ON grp.id = pr.via_group_id
                  JOIN identity.role_permission rp
                       ON rp.role_id = pr.role_id
                           AND rp.validity && pr.validity
         WHERE pr.via_group_id IS NULL OR grp.is_active
     ) g
         JOIN identity.active_principal ap
              ON ap.principal_type = g.principal_type
                  AND ap.principal_id   = g.principal_id;

CREATE OR REPLACE FUNCTION create_crud_permissions(p_content_type_id citext DEFAULT NULL)
    RETURNS integer
    LANGUAGE plpgsql
AS $$
DECLARE
    affected integer;
BEGIN
    INSERT INTO config.permission (content_type_id, permission_id, description, is_targeted)
    SELECT
        ct.id,
        a.action,
        format('%s %s', a.verb, COALESCE(ct.display, ct.id)),
        COALESCE(cardinality(ct.targetable_fields), 0) > 0
    FROM config.content_type ct
             CROSS JOIN (VALUES
                             ('create', 'Create'),
                             ('read',   'Read'),
                             ('update', 'Update'),
                             ('delete', 'Delete')
    ) AS a(action, verb)
    WHERE p_content_type_id IS NULL OR ct.id = p_content_type_id
    ON CONFLICT (content_type_id, permission_id) DO UPDATE
        SET is_targeted = EXCLUDED.is_targeted
    WHERE permission.is_targeted IS DISTINCT FROM EXCLUDED.is_targeted;

    GET DIAGNOSTICS affected = ROW_COUNT;
    RETURN affected;
END;
$$;

CREATE OR REPLACE FUNCTION content_type_create_permissions()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    PERFORM create_crud_permissions(NEW.id);
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION grant_sync_target()
    RETURNS trigger
    LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.is_targeted THEN
        -- becoming targeted: an untargeted grant meant "all rows"
        NEW.target := COALESCE(NEW.target, '"*"'::jsonb);
    ELSIF NEW.target = '"*"'::jsonb THEN
        -- becoming untargeted: a wildcard grant stays "all rows"
        NEW.target := NULL;
    ELSIF NEW.target IS NOT NULL THEN
        -- dropping a specific target would widen access, so refuse
        RAISE EXCEPTION
            'grant % has a specific target; revoke or replace it before making %.% untargeted',
            NEW.id, NEW.permission_content_type_id, NEW.permission_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_content_type_permissions
    AFTER INSERT OR UPDATE OF targetable_fields ON config.content_type
    FOR EACH ROW EXECUTE FUNCTION content_type_create_permissions();

CREATE TRIGGER trg_user_permission_sync_target
    BEFORE UPDATE ON identity.user_permission
    FOR EACH ROW WHEN (OLD.is_targeted IS DISTINCT FROM NEW.is_targeted)
EXECUTE FUNCTION grant_sync_target();

CREATE TRIGGER trg_device_permission_sync_target
    BEFORE UPDATE ON identity.device_permission
    FOR EACH ROW WHEN (OLD.is_targeted IS DISTINCT FROM NEW.is_targeted)
EXECUTE FUNCTION grant_sync_target();

CREATE TRIGGER trg_service_permission_sync_target
    BEFORE UPDATE ON identity.service_permission
    FOR EACH ROW WHEN (OLD.is_targeted IS DISTINCT FROM NEW.is_targeted)
EXECUTE FUNCTION grant_sync_target();

CREATE TRIGGER trg_role_permission_sync_target
    BEFORE UPDATE ON identity.role_permission
    FOR EACH ROW WHEN (OLD.is_targeted IS DISTINCT FROM NEW.is_targeted)
EXECUTE FUNCTION grant_sync_target();

SELECT create_crud_permissions();