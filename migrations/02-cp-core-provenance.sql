CREATE SCHEMA IF NOT EXISTS provenance;

CREATE TYPE provenance.audit_event_type AS ENUM ('create', 'retrieve', 'update', 'delete');
CREATE TYPE provenance.record_status AS ENUM ('current', 'superseded', 'corrected', 'in_error', 'cancelled', 'amended', 'deleted');

CREATE TABLE provenance.event_log
(
    id              UUID DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    content_type_id citext                            NOT NULL REFERENCES config.content_type (id),
    record_id       jsonb                             NOT NULL,
    event_type      provenance.audit_event_type                  NOT NULL,
    actor           jsonb                             NOT NULL,
    timestamp       timestamptz                       NOT NULL DEFAULT now(),
    old_snapshot    jsonb,
    new_snapshot    jsonb,

    CONSTRAINT chk_diff CHECK (
        CASE event_type
            WHEN 'create'   THEN old_snapshot IS NULL     AND new_snapshot IS NOT NULL
            WHEN 'update'   THEN old_snapshot IS NOT NULL AND new_snapshot IS NOT NULL
            WHEN 'delete'   THEN old_snapshot IS NOT NULL AND new_snapshot IS NULL
            WHEN 'retrieve' THEN old_snapshot IS NULL     AND new_snapshot IS NULL
            ELSE false
        END
    )
);

INSERT INTO config.content_type VALUES ('event_log', 'Event Log');

CREATE INDEX ON provenance.event_log (content_type_id, record_id);
CREATE INDEX ON provenance.event_log USING brin (timestamp);

-- TODO: REVOKE UPDATE, DELETE ON event_log FROM <app_role>