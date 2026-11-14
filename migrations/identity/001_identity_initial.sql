CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS btree_gist;

CREATE TYPE audit_event_type AS ENUM ('create', 'retrieve', 'update', 'delete');
CREATE TYPE device_status AS ENUM ('provisioning', 'active', 'suspended', 'revoked', 'decommissioned');
CREATE TYPE device_trust_level AS ENUM ('managed', 'trusted_internal', 'trusted_external');
CREATE TYPE name_use AS ENUM ('usual', 'official', 'temp', 'nickname', 'anonymous', 'old', 'maiden');
CREATE TYPE contact_system AS ENUM ('phone', 'fax', 'email', 'pager', 'url', 'sms', 'other');
CREATE TYPE contact_use AS ENUM ('home', 'work', 'temp', 'old', 'mobile');
CREATE TYPE fhir_user_resource_type AS ENUM ('Practitioner', 'Patient', 'RelatedPerson');
CREATE TYPE delegation_status AS ENUM ('pending', 'active', 'revoked');
CREATE TYPE fga_op_type AS ENUM ('write', 'delete');

CREATE TABLE lang
(
    id      CITEXT PRIMARY KEY NOT NULL,
    display CITEXT             NOT NULL,
    endonym CITEXT DEFAULT NULL
);

INSERT INTO lang (id, display, endonym) VALUES
                                                   ('en', 'English', 'English'),
                                                   ('aa', 'Afar', 'Qafaraf'),
                                                   ('ab', 'Abkhazian', 'Аԥсшәа'),
                                                   ('ae', 'Avestan', 'Avesta'),
                                                   ('af', 'Afrikaans', 'Afrikaans'),
                                                   ('ak', 'Akan', 'Akan'),
                                                   ('am', 'Amharic', 'አማርኛ'),
                                                   ('an', 'Aragonese', 'Aragonés'),
                                                   ('ar', 'Arabic', 'العربية'),
                                                   ('as', 'Assamese', 'অসমীয়া'),
                                                   ('av', 'Avaric', 'Авар мацӀ'),
                                                   ('ay', 'Aymara', 'Aymar aru'),
                                                   ('az', 'Azerbaijani', 'Azərbaycan dili'),
                                                   ('ba', 'Bashkir', 'Башҡорт теле'),
                                                   ('be', 'Belarusian', 'Беларуская'),
                                                   ('bg', 'Bulgarian', 'Български'),
                                                   ('bi', 'Bislama', 'Bislama'),
                                                   ('bm', 'Bambara', 'Bamanankan'),
                                                   ('bn', 'Bengali', 'বাংলা'),
                                                   ('bo', 'Tibetan', 'བོད་ཡིག'),
                                                   ('br', 'Breton', 'Brezhoneg'),
                                                   ('bs', 'Bosnian', 'Bosanski'),
                                                   ('ca', 'Catalan', 'Català'),
                                                   ('ce', 'Chechen', 'Нохчийн мотт'),
                                                   ('ch', 'Chamorro', 'Chamoru'),
                                                   ('co', 'Corsican', 'Corsu'),
                                                   ('cr', 'Cree', 'ᓀᐦᐃᔭᐍᐏᐣ'),
                                                   ('cs', 'Czech', 'Čeština'),
                                                   ('cu', 'Church Slavic', 'Ѩзыкъ словѣньскъ'),
                                                   ('cv', 'Chuvash', 'Чӑвашла'),
                                                   ('cy', 'Welsh', 'Cymraeg'),
                                                   ('da', 'Danish', 'Dansk'),
                                                   ('de', 'German', 'Deutsch'),
                                                   ('dv', 'Divehi', 'ދިވެހި'),
                                                   ('dz', 'Dzongkha', 'རྫོང་ཁ'),
                                                   ('ee', 'Ewe', 'Eʋegbe'),
                                                   ('el', 'Greek', 'Ελληνικά'),
                                                   ('eo', 'Esperanto', 'Esperanto'),
                                                   ('es', 'Spanish', 'Español'),
                                                   ('et', 'Estonian', 'Eesti'),
                                                   ('eu', 'Basque', 'Euskara'),
                                                   ('fa', 'Persian', 'فارسی'),
                                                   ('ff', 'Fulah', 'Fulfulde'),
                                                   ('fi', 'Finnish', 'Suomi'),
                                                   ('fj', 'Fijian', 'Vosa Vakaviti'),
                                                   ('fo', 'Faroese', 'Føroyskt'),
                                                   ('fr', 'French', 'Français'),
                                                   ('fy', 'Western Frisian', 'Frysk'),
                                                   ('ga', 'Irish', 'Gaeilge'),
                                                   ('gd', 'Scottish Gaelic', 'Gàidhlig'),
                                                   ('gl', 'Galician', 'Galego'),
                                                   ('gn', 'Guarani', 'Avañe''ẽ'),
                                                   ('gu', 'Gujarati', 'ગુજરાતી'),
                                                   ('gv', 'Manx', 'Gaelg'),
                                                   ('ha', 'Hausa', 'Hausa'),
                                                   ('he', 'Hebrew', 'עברית'),
                                                   ('hi', 'Hindi', 'हिन्दी'),
                                                   ('ho', 'Hiri Motu', 'Hiri Motu'),
                                                   ('hr', 'Croatian', 'Hrvatski'),
                                                   ('ht', 'Haitian Creole', 'Kreyòl ayisyen'),
                                                   ('hu', 'Hungarian', 'Magyar'),
                                                   ('hy', 'Armenian', 'Հայերեն'),
                                                   ('hz', 'Herero', 'Otjiherero'),
                                                   ('ia', 'Interlingua', 'Interlingua'),
                                                   ('id', 'Indonesian', 'Bahasa Indonesia'),
                                                   ('ie', 'Interlingue', 'Interlingue'),
                                                   ('ig', 'Igbo', 'Asụsụ Igbo'),
                                                   ('ii', 'Sichuan Yi', 'ꆈꌠꉙ'),
                                                   ('ik', 'Inupiaq', 'Iñupiaq'),
                                                   ('io', 'Ido', 'Ido'),
                                                   ('is', 'Icelandic', 'Íslenska'),
                                                   ('it', 'Italian', 'Italiano'),
                                                   ('iu', 'Inuktitut', 'ᐃᓄᒃᑎᑐᑦ'),
                                                   ('ja', 'Japanese', '日本語'),
                                                   ('jv', 'Javanese', 'Basa Jawa'),
                                                   ('ka', 'Georgian', 'ქართული'),
                                                   ('kg', 'Kongo', 'Kikongo'),
                                                   ('ki', 'Kikuyu', 'Gĩkũyũ'),
                                                   ('kj', 'Kuanyama', 'Oshikwanyama'),
                                                   ('kk', 'Kazakh', 'Қазақ тілі'),
                                                   ('kl', 'Kalaallisut', 'Kalaallisut'),
                                                   ('km', 'Khmer', 'ភាសាខ្មែរ'),
                                                   ('kn', 'Kannada', 'ಕನ್ನಡ'),
                                                   ('ko', 'Korean', '한국어'),
                                                   ('kr', 'Kanuri', 'Kanuri'),
                                                   ('ks', 'Kashmiri', 'كٲشُر'),
                                                   ('ku', 'Kurdish', 'Kurdî'),
                                                   ('kv', 'Komi', 'Коми кыв'),
                                                   ('kw', 'Cornish', 'Kernewek'),
                                                   ('ky', 'Kyrgyz', 'Кыргызча'),
                                                   ('la', 'Latin', 'Latina'),
                                                   ('lb', 'Luxembourgish', 'Lëtzebuergesch'),
                                                   ('lg', 'Ganda', 'Luganda'),
                                                   ('li', 'Limburgish', 'Limburgs'),
                                                   ('ln', 'Lingala', 'Lingála'),
                                                   ('lo', 'Lao', 'ລາວ'),
                                                   ('lt', 'Lithuanian', 'Lietuvių'),
                                                   ('lu', 'Luba-Katanga', 'Kiluba'),
                                                   ('lv', 'Latvian', 'Latviešu'),
                                                   ('mg', 'Malagasy', 'Malagasy'),
                                                   ('mh', 'Marshallese', 'Kajin M̧ajeļ'),
                                                   ('mi', 'Māori', 'Te reo Māori'),
                                                   ('mk', 'Macedonian', 'Македонски'),
                                                   ('ml', 'Malayalam', 'മലയാളം'),
                                                   ('mn', 'Mongolian', 'Монгол'),
                                                   ('mr', 'Marathi', 'मराठी'),
                                                   ('ms', 'Malay', 'Bahasa Melayu'),
                                                   ('mt', 'Maltese', 'Malti'),
                                                   ('my', 'Burmese', 'မြန်မာဘာသာ'),
                                                   ('na', 'Nauruan', 'Dorerin Naoero'),
                                                   ('nb', 'Norwegian Bokmål', 'Norsk bokmål'),
                                                   ('nd', 'North Ndebele', 'isiNdebele'),
                                                   ('ne', 'Nepali', 'नेपाली'),
                                                   ('ng', 'Ndonga', 'Owambo'),
                                                   ('nl', 'Dutch', 'Nederlands'),
                                                   ('nn', 'Norwegian Nynorsk', 'Norsk nynorsk'),
                                                   ('no', 'Norwegian', 'Norsk'),
                                                   ('nr', 'South Ndebele', 'isiNdebele'),
                                                   ('nv', 'Navajo', 'Diné bizaad'),
                                                   ('ny', 'Chichewa', 'Chichewa'),
                                                   ('oc', 'Occitan', 'Occitan'),
                                                   ('oj', 'Ojibwe', 'ᐊᓂᔑᓈᐯᒧᐎᓐ'),
                                                   ('om', 'Oromo', 'Afaan Oromoo'),
                                                   ('or', 'Odia', 'ଓଡ଼ିଆ'),
                                                   ('os', 'Ossetian', 'Ирон æвзаг'),
                                                   ('pa', 'Punjabi', 'ਪੰਜਾਬੀ'),
                                                   ('pi', 'Pali', 'पालि'),
                                                   ('pl', 'Polish', 'Polski'),
                                                   ('ps', 'Pashto', 'پښتو'),
                                                   ('pt', 'Portuguese', 'Português'),
                                                   ('qu', 'Quechua', 'Runa Simi'),
                                                   ('rm', 'Romansh', 'Rumantsch'),
                                                   ('rn', 'Kirundi', 'Ikirundi'),
                                                   ('ro', 'Romanian', 'Română'),
                                                   ('ru', 'Russian', 'Русский'),
                                                   ('rw', 'Kinyarwanda', 'Kinyarwanda'),
                                                   ('sa', 'Sanskrit', 'संस्कृतम्'),
                                                   ('sc', 'Sardinian', 'Sardu'),
                                                   ('sd', 'Sindhi', 'سنڌي'),
                                                   ('se', 'Northern Sami', 'Davvisámegiella'),
                                                   ('sg', 'Sango', 'Sängö'),
                                                   ('si', 'Sinhala', 'සිංහල'),
                                                   ('sk', 'Slovak', 'Slovenčina'),
                                                   ('sl', 'Slovenian', 'Slovenščina'),
                                                   ('sm', 'Samoan', 'Gagana Samoa'),
                                                   ('sn', 'Shona', 'chiShona'),
                                                   ('so', 'Somali', 'Soomaali'),
                                                   ('sq', 'Albanian', 'Shqip'),
                                                   ('sr', 'Serbian', 'Српски'),
                                                   ('ss', 'Swati', 'SiSwati'),
                                                   ('st', 'Southern Sotho', 'Sesotho'),
                                                   ('su', 'Sundanese', 'Basa Sunda'),
                                                   ('sv', 'Swedish', 'Svenska'),
                                                   ('sw', 'Swahili', 'Kiswahili'),
                                                   ('ta', 'Tamil', 'தமிழ்'),
                                                   ('te', 'Telugu', 'తెలుగు'),
                                                   ('tg', 'Tajik', 'Тоҷикӣ'),
                                                   ('th', 'Thai', 'ไทย'),
                                                   ('ti', 'Tigrinya', 'ትግርኛ'),
                                                   ('tk', 'Turkmen', 'Türkmençe'),
                                                   ('tl', 'Tagalog', 'Tagalog'),
                                                   ('tn', 'Tswana', 'Setswana'),
                                                   ('to', 'Tongan', 'Lea faka-Tonga'),
                                                   ('tr', 'Turkish', 'Türkçe'),
                                                   ('ts', 'Tsonga', 'Xitsonga'),
                                                   ('tt', 'Tatar', 'Татарча'),
                                                   ('tw', 'Twi', 'Twi'),
                                                   ('ty', 'Tahitian', 'Reo Tahiti'),
                                                   ('ug', 'Uyghur', 'ئۇيغۇرچە'),
                                                   ('uk', 'Ukrainian', 'Українська'),
                                                   ('ur', 'Urdu', 'اردو'),
                                                   ('uz', 'Uzbek', 'Oʻzbekcha'),
                                                   ('ve', 'Venda', 'Tshivenḓa'),
                                                   ('vi', 'Vietnamese', 'Tiếng Việt'),
                                                   ('vo', 'Volapük', 'Volapük'),
                                                   ('wa', 'Walloon', 'Walon'),
                                                   ('wo', 'Wolof', 'Wolof'),
                                                   ('xh', 'Xhosa', 'isiXhosa'),
                                                   ('yi', 'Yiddish', 'ייִדיש'),
                                                   ('yo', 'Yoruba', 'Yorùbá'),
                                                   ('za', 'Zhuang', 'Saɯ cueŋƅ'),
                                                   ('zh', 'Chinese', '中文'),
                                                   ('zu', 'Zulu', 'isiZulu');

CREATE TABLE event_log
(
    id           UUID                      DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    content_type TEXT             NOT NULL,
    record_id    JSONB            NOT NULL,
    event_type   audit_event_type NOT NULL,
    actor        JSONB            NOT NULL,
    timestamp    TIMESTAMPTZ      NOT NULL DEFAULT now(),
    old_snapshot JSONB,
    new_snapshot JSONB,

    CONSTRAINT chk_diff CHECK (
        CASE event_type
            WHEN 'create' THEN old_snapshot IS NULL AND new_snapshot IS NOT NULL
            WHEN 'update' THEN old_snapshot IS NOT NULL AND new_snapshot IS NOT NULL
            WHEN 'delete' THEN old_snapshot IS NOT NULL AND new_snapshot IS NULL
            WHEN 'retrieve' THEN old_snapshot IS NULL AND new_snapshot IS NULL
            ELSE false
            END
        )
);

CREATE INDEX ON event_log (content_type, record_id);
CREATE INDEX ON event_log USING brin (timestamp);

CREATE TABLE clinical_environment (
    id CITEXT PRIMARY KEY,
    display TEXT NOT NULL,
    base_url TEXT NOT NULL UNIQUE
);

CREATE TABLE user_profile (
                              id UUID PRIMARY KEY DEFAULT uuidv7(),
                              idp_id UUID NOT NULL UNIQUE,
                              active BOOLEAN NOT NULL DEFAULT TRUE,
                              external_id TEXT,
                              employee_id TEXT,
                              cost_center TEXT,
                              organization TEXT,
                              division TEXT,
                              department TEXT,
                              manager_id UUID REFERENCES user_profile (id),
                              photo_url TEXT,
                              preferred_language_id CITEXT REFERENCES lang (id) NOT NULL DEFAULT 'en'
);

CREATE INDEX ON user_profile(manager_id);
CREATE UNIQUE INDEX ix_user_profile_external_id_key    ON user_profile (external_id)    WHERE external_id IS NOT NULL;
CREATE UNIQUE INDEX ix_user_profile_employee_id_key    ON user_profile (employee_id)    WHERE employee_id IS NOT NULL;

CREATE TABLE launch_context
(
    id                  UUID PRIMARY KEY     DEFAULT gen_random_uuid(),
    environment_id      CITEXT      NOT NULL REFERENCES clinical_environment(id),
    subject             UUID        NOT NULL REFERENCES user_profile(idp_id),
    client_id           TEXT        NOT NULL,
    patient_id          TEXT,
    encounter_id        TEXT,
    fhir_context        JSONB       NOT NULL DEFAULT '[]',
    need_patient_banner BOOLEAN     NOT NULL,
    created             TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires             TIMESTAMPTZ NOT NULL,
    consumed            TIMESTAMPTZ          DEFAULT NULL,

    CHECK ( expires > created )
);

CREATE INDEX ON launch_context (expires);

CREATE TABLE "group"
(
    id          UUID PRIMARY KEY DEFAULT uuidv7(),
    external_id TEXT        NOT NULL UNIQUE,
    display     TEXT        NOT NULL
);

CREATE TABLE user_name
(
    id       UUID                DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id  UUID       NOT NULL REFERENCES user_profile (id),
    use      name_use   NOT NULL,
    family_name CITEXT,
    given_name  CITEXT[],
    prefix      CITEXT[],
    suffix      CITEXT[],
    validity tstzrange  NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (user_id WITH =, use WITH =, validity WITH &&) WHERE (use IN ('official', 'usual'))
);

CREATE TABLE user_contact_point
(
    id       UUID                    DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id  UUID           NOT NULL REFERENCES user_profile (id),
    system   contact_system NOT NULL,
    use      contact_use    NOT NULL,
    value    CITEXT         NOT NULL,
    rank     SMALLINT CHECK ( rank > 0 ),
    validity tstzrange      NOT NULL DEFAULT tstzrange(NOW(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    verified timestamptz
);

CREATE INDEX ON user_contact_point(user_id);

CREATE TABLE fhir_user_link
(
    user_id        UUID                    NOT NULL REFERENCES user_profile (id),
    environment_id CITEXT                  NOT NULL REFERENCES clinical_environment(id),
    resource_type  fhir_user_resource_type NOT NULL,
    resource_id    TEXT                    NOT NULL CHECK (resource_id ~ '^[A-Za-z0-9\-\.]{1,64}$'),
    linked_by      uuid                    NOT NULL REFERENCES user_profile (id),
    linked_at      timestamptz             NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, environment_id),
    UNIQUE (environment_id, resource_type, resource_id)
);

CREATE TABLE delegation_type (
    id CITEXT PRIMARY KEY NOT NULL,
    display TEXT NOT NULL
);

CREATE TABLE delegation
(
    id                UUID PRIMARY KEY  NOT NULL DEFAULT uuidv7(),
    type              CITEXT            NOT NULL REFERENCES delegation_type (id),
    status            delegation_status NOT NULL DEFAULT 'pending',
    delegator_id      UUID              NOT NULL,
    delegate_id       UUID              NOT NULL,
    scope             TEXT              NOT NULL,
    reason            TEXT              NOT NULL,
    validity          TSTZRANGE         NOT NULL,
    created_by_id     UUID              NOT NULL REFERENCES user_profile (idp_id),
    created_at        TIMESTAMPTZ       NOT NULL DEFAULT now(),
    approved_by_id    UUID REFERENCES user_profile (idp_id),
    approved_at       TIMESTAMPTZ,
    revoked_by_id     UUID REFERENCES user_profile (idp_id),
    revoked_at        TIMESTAMPTZ,
    revocation_reason TEXT,

    CHECK (delegator_id <> delegate_id),
    CHECK (NOT isempty(validity) AND upper(validity) IS NOT NULL),
    CHECK (NOT isempty(validity) AND upper(validity) < 'infinity'),
    CHECK ((status = 'active') = (approved_at IS NOT NULL AND revoked_at IS NULL)),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
    CHECK (approved_by_id IS NULL OR approved_by_id <> delegate_id),
    CHECK ((approved_by_id IS NULL) = (approved_at IS NULL)),
    CHECK ((revoked_by_id  IS NULL) = (revoked_at  IS NULL)),
    CHECK ( approved_by_id IS NULL OR approved_by_id <> created_by_id ),

    EXCLUDE USING gist (delegator_id WITH =, delegate_id WITH =, scope WITH =, validity WITH &&) WHERE (status <> 'revoked')
);

CREATE INDEX ON delegation (delegate_id) WHERE status = 'active';
CREATE INDEX ON delegation (delegator_id) WHERE status = 'active';

CREATE TABLE device_type
(
    id          CITEXT NOT NULL PRIMARY KEY,
    description TEXT
);

INSERT INTO device_type (id, description) VALUES
                                                       ('workstation', 'Workstation'),
                                                       ('shared', 'Shared Workstation'),
                                                       ('kiosk', 'Kiosk');

CREATE TABLE device
(
    id       UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    name     TEXT,
    location TEXT,
    status   device_status                     NOT NULL,
    trust    device_trust_level,
    type_id  CITEXT                            NOT NULL REFERENCES device_type (id)
);

CREATE TABLE device_certificate
(
    id         UUID               DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id  UUID      NOT NULL REFERENCES device (id),
    thumbprint BYTEA     NOT NULL UNIQUE CHECK (octet_length(thumbprint) = 32),
    public_key BYTEA     NOT NULL,
    issuer_dn  TEXT      NOT NULL,
    serial     TEXT      NOT NULL,
    validity   tstzrange NOT NULL CHECK (NOT isempty(validity)),
    UNIQUE (issuer_dn, serial)
);

CREATE TABLE device_downtime_region
(
    device_id UUID      NOT NULL REFERENCES device (id),
    region_id UUID      NOT NULL,
    validity  tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (device_id WITH =, region_id WITH =, validity WITH &&)
);

CREATE TABLE device_auth_attempt
(
    id             UUID                  DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id      UUID         NOT NULL REFERENCES device (id),
    application_id VARCHAR(255) NOT NULL,
    timestamp      timestamptz  NOT NULL DEFAULT now(),
    is_success     BOOLEAN      NOT NULL
);

CREATE TABLE idlink_device_policy
(
    id          UUID             DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    device_id   UUID    NOT NULL REFERENCES device (id),
    name        CITEXT  NOT NULL,
    version     SMALLINT NOT NULL CHECK ( version > 0 ),
    description TEXT,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    data        JSONB   NOT NULL,
    UNIQUE (device_id, name, version)
);


CREATE TABLE idlink
(
    id        UUID               DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    user_id   UUID      NOT NULL REFERENCES user_profile (id),
    device_id UUID      NOT NULL REFERENCES device (id),
    validity  tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    EXCLUDE using gist (user_id WITH =, device_id WITH =, validity WITH &&)
);

CREATE TABLE idlink_session
(
    idlink_id  UUID      NOT NULL REFERENCES idlink (id),
    session_id UUID NOT NULL,
    validity   tstzrange NOT NULL DEFAULT tstzrange(now(), 'infinity', '[)') CHECK (NOT isempty(validity)),
    PRIMARY KEY (idlink_id, session_id)
);

CREATE TABLE fga_outbox
(
    id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    op         fga_op_type NOT NULL,
    tuple      jsonb       NOT NULL,
    source_id  uuid        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    sent_at    timestamptz,
    attempts   int         NOT NULL DEFAULT 0,
    last_error text
);

CREATE INDEX ON fga_outbox (id) WHERE sent_at IS NULL;

CREATE INDEX ON device_certificate   (device_id);
CREATE INDEX ON device               (type_id);
CREATE INDEX ON idlink               (device_id);
CREATE INDEX ON idlink_session       (session_id);
CREATE INDEX ON device_auth_attempt  (device_id, timestamp DESC);


---- create above / drop below ----


DROP TABLE IF EXISTS fga_outbox;

DROP TABLE IF EXISTS idlink_session;
DROP TABLE IF EXISTS idlink;
DROP TABLE IF EXISTS idlink_device_policy;
DROP TABLE IF EXISTS device_auth_attempt;
DROP TABLE IF EXISTS device_downtime_region;
DROP TABLE IF EXISTS device_certificate;
DROP TABLE IF EXISTS device;
DROP TABLE IF EXISTS device_type;

DROP TABLE IF EXISTS delegation;
DROP TABLE IF EXISTS delegation_type;

DROP TABLE IF EXISTS fhir_user_link;
DROP TABLE IF EXISTS user_contact_point;
DROP TABLE IF EXISTS user_name;
DROP TABLE IF EXISTS "group";
DROP TABLE IF EXISTS launch_context;

DROP TABLE IF EXISTS user_profile;
DROP TABLE IF EXISTS clinical_environment;
DROP TABLE IF EXISTS event_log;
DROP TABLE IF EXISTS lang;

DROP TYPE IF EXISTS fga_op_type;
DROP TYPE IF EXISTS delegation_status;
DROP TYPE IF EXISTS fhir_user_resource_type;
DROP TYPE IF EXISTS contact_use;
DROP TYPE IF EXISTS contact_system;
DROP TYPE IF EXISTS name_use;
DROP TYPE IF EXISTS device_trust_level;
DROP TYPE IF EXISTS device_status;
DROP TYPE IF EXISTS audit_event_type;