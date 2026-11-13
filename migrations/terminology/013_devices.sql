CREATE TABLE umdns_release (
    version_id   uuid PRIMARY KEY,
    code_system  citext NOT NULL DEFAULT 'umdns' CHECK (code_system = 'umdns'),
    FOREIGN KEY (version_id, code_system) REFERENCES code_system_version (id, code_system_id) ON DELETE CASCADE
);

CREATE TABLE umdns_category (
    version_id    uuid NOT NULL REFERENCES umdns_release (version_id) ON DELETE CASCADE,
    code          text NOT NULL CHECK (code ~ '^[0-9]{5}$'),
    name          text NOT NULL,
    definition    text,
    active        boolean NOT NULL DEFAULT true,
    parent_code   text,
    PRIMARY KEY (version_id, code),
    FOREIGN KEY (version_id, parent_code) REFERENCES umdns_category (version_id, code) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE umdns_entry_term (
    version_id    uuid NOT NULL REFERENCES umdns_release (version_id) ON DELETE CASCADE,
    code         text NOT NULL,
    term         text NOT NULL,
    PRIMARY KEY (version_id, code, term),
    FOREIGN KEY (version_id, code) REFERENCES umdns_category (version_id, code) ON DELETE CASCADE
);


---- create above / drop below ----


DROP TABLE umdns_entry_term;
DROP TABLE umdns_category;
DROP TABLE umdns_release;
