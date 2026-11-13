CREATE TABLE terms.chv_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'chv' CHECK (code_system = 'chv'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version (id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.chv_term (
    version_id      uuid NOT NULL REFERENCES terms.chv_release (version_id) ON DELETE CASCADE,
    code            text NOT NULL,
    term            text NOT NULL,
    umls_cui        text NOT NULL,
    preferred       boolean NOT NULL DEFAULT false,
    combined_score  numeric,
    PRIMARY KEY (version_id, code)
);

CREATE INDEX chv_term_by_cui   ON terms.chv_term (version_id, umls_cui);
CREATE INDEX chv_term_trgm     ON terms.chv_term USING gin (term gin_trgm_ops);


CREATE TABLE terms.medlineplus_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'medlineplus' CHECK (code_system = 'medlineplus'),
    FOREIGN KEY (version_id, code_system) REFERENCES terms.code_system_version (id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE terms.medlineplus_topic (
    version_id            uuid NOT NULL REFERENCES terms.medlineplus_release (version_id) ON DELETE CASCADE,
    topic_id              text NOT NULL CHECK (topic_id ~ '^[0-9]+$'),
    title                 text NOT NULL,
    url                   text NOT NULL,
    language              text NOT NULL CHECK (language IN ('English', 'Spanish')),
    other_language_topic  text,
    PRIMARY KEY (version_id, topic_id),
    FOREIGN KEY (version_id, other_language_topic)
        REFERENCES terms.medlineplus_topic (version_id, topic_id)
        DEFERRABLE INITIALLY DEFERRED
);

CREATE INDEX medlineplus_topic_title_trgm ON terms.medlineplus_topic USING gin (title gin_trgm_ops);

CREATE TABLE terms.medlineplus_topic_alias (
    version_id   uuid NOT NULL REFERENCES terms.medlineplus_release (version_id) ON DELETE CASCADE,
    topic_id     text NOT NULL,
    alias        text NOT NULL,
    PRIMARY KEY (version_id, topic_id, alias),
    FOREIGN KEY (version_id, topic_id) REFERENCES terms.medlineplus_topic (version_id, topic_id) ON DELETE CASCADE
);

CREATE TABLE terms.medlineplus_topic_group (
    version_id   uuid NOT NULL REFERENCES terms.medlineplus_release (version_id) ON DELETE CASCADE,
    topic_id     text NOT NULL,
    group_name   text NOT NULL,
    PRIMARY KEY (version_id, topic_id, group_name),
    FOREIGN KEY (version_id, topic_id) REFERENCES terms.medlineplus_topic (version_id, topic_id) ON DELETE CASCADE
);

CREATE TABLE terms.medlineplus_related_topic (
    version_id        uuid NOT NULL REFERENCES terms.medlineplus_release (version_id) ON DELETE CASCADE,
    topic_id          text NOT NULL,
    related_topic_id  text NOT NULL,
    PRIMARY KEY (version_id, topic_id, related_topic_id),
    FOREIGN KEY (version_id, topic_id)         REFERENCES terms.medlineplus_topic (version_id, topic_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED,
    FOREIGN KEY (version_id, related_topic_id) REFERENCES terms.medlineplus_topic (version_id, topic_id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);