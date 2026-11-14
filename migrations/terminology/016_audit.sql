-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T5 / ROADMAP D13: who changed what, and when.
--
-- * code_system_version gets its provenance columns: source_sha256 (the release's SHA-256, part of
--   the cross-instance identity (code_system_id, version, source_sha256), rule 4b), validated_at,
--   activated_at and activated_by.
-- * version_activation_log records every activation and rollback.
-- * terms_audit_event is the append-only audit trail. Capture triggers write it; nothing else
--   inserts into it except record_denied_attempt() for the authz interceptor. A guard trigger
--   rejects UPDATE, DELETE and TRUNCATE for every role, including the owner.
--
-- Within a mutating API request the service sets, transaction-locally (set_config(..., true)):
--   terms.actor       JSON: {"issuer","subject","client_id","display","scopes"}
--   terms.request_id  text
--   terms.reason      text
-- A change made without terms.actor (psql, a migration) is recorded with source = 'db' and the
-- session's DB role as the actor.
--
-- Triggers for value_set and terms_job are added by the migrations that create those tables:
--   CREATE TRIGGER <t>_audit AFTER INSERT OR UPDATE OR DELETE ON <t>
--       FOR EACH ROW EXECUTE FUNCTION audit_capture('<natural key column>', ...);

ALTER TABLE code_system_version
    ADD COLUMN source_sha256 TEXT CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    ADD COLUMN validated_at  timestamptz,
    ADD COLUMN activated_at  timestamptz,
    ADD COLUMN activated_by  jsonb;

-- Required for new versions. NOT VALID because rows installed before this migration have no
-- checksum; such a row must get its source_sha256 set before any other update to it succeeds.
ALTER TABLE code_system_version
    ADD CONSTRAINT code_system_version_source_sha256_required CHECK (source_sha256 IS NOT NULL) NOT VALID;

-- The natural identity of a version never changes once set.
CREATE FUNCTION code_system_version_identity_immutable()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.code_system_id IS DISTINCT FROM OLD.code_system_id
        OR NEW.version IS DISTINCT FROM OLD.version
        OR (OLD.source_sha256 IS NOT NULL AND NEW.source_sha256 IS DISTINCT FROM OLD.source_sha256) THEN
        RAISE EXCEPTION 'code_system_version % : code_system_id, version and source_sha256 are immutable', OLD.id;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER code_system_version_identity
    BEFORE UPDATE ON code_system_version
    FOR EACH ROW EXECUTE FUNCTION code_system_version_identity_immutable();

-- The actor of the current transaction: terms.actor if the API set it, else the DB role.
CREATE FUNCTION terms_current_actor()
    RETURNS jsonb
    LANGUAGE sql STABLE AS $$
SELECT COALESCE(NULLIF(current_setting('terms.actor', true), '')::jsonb,
                jsonb_build_object('db_role', session_user::text))
$$;

CREATE FUNCTION terms_current_source()
    RETURNS text
    LANGUAGE sql STABLE AS $$
SELECT CASE WHEN NULLIF(current_setting('terms.actor', true), '') IS NULL THEN 'db' ELSE 'api' END
$$;

CREATE TYPE version_activation_action AS ENUM ('activate', 'rollback');

CREATE TABLE version_activation_log
(
    id              UUID DEFAULT uuidv7() PRIMARY KEY,
    code_system_id  CITEXT NOT NULL REFERENCES code_system (id),
    from_version_id UUID REFERENCES code_system_version (id) ON DELETE SET NULL,
    to_version_id   UUID REFERENCES code_system_version (id) ON DELETE SET NULL,
    action          version_activation_action NOT NULL,
    actor           jsonb NOT NULL,
    request_id      TEXT,
    reason          TEXT,
    at              timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE INDEX version_activation_log_system ON version_activation_log (code_system_id, at DESC);

CREATE TABLE terms_audit_event
(
    id           UUID DEFAULT uuidv7() PRIMARY KEY,
    at           timestamptz NOT NULL DEFAULT clock_timestamp(),
    source       TEXT NOT NULL CHECK (source IN ('api', 'db')),
    actor        jsonb NOT NULL,
    request_id   TEXT,
    reason       TEXT,
    action       TEXT NOT NULL,
    target_table TEXT NOT NULL,
    target       jsonb NOT NULL,   -- natural key (D6a); never an instance-local version_id
    before       jsonb,
    after        jsonb,
    outcome      TEXT NOT NULL DEFAULT 'ok' CHECK (outcome IN ('ok', 'denied'))
);

CREATE INDEX terms_audit_event_at ON terms_audit_event (at);
CREATE INDEX terms_audit_event_target ON terms_audit_event (target_table, at);

CREATE FUNCTION terms_audit_event_append_only()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'terms_audit_event is append-only (% rejected)', TG_OP;
END
$$;

CREATE TRIGGER terms_audit_event_no_update_delete
    BEFORE UPDATE OR DELETE ON terms_audit_event
    FOR EACH ROW EXECUTE FUNCTION terms_audit_event_append_only();

CREATE TRIGGER terms_audit_event_no_truncate
    BEFORE TRUNCATE ON terms_audit_event
    FOR EACH STATEMENT EXECUTE FUNCTION terms_audit_event_append_only();

-- Capture trigger. Arguments are the natural-key columns recorded as the target. The row images
-- drop "id": internal surrogate ids don't leave the instance (rule 4b); the target carries the
-- natural key instead.
CREATE FUNCTION audit_capture()
    RETURNS trigger
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = public, pg_temp AS $$
DECLARE
    v_row    jsonb := to_jsonb(CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END);
    v_target jsonb := '{}';
    v_key    text;
BEGIN
    FOREACH v_key IN ARRAY TG_ARGV LOOP
        v_target := v_target || jsonb_build_object(v_key, v_row -> v_key);
    END LOOP;

    INSERT INTO terms_audit_event (source, actor, request_id, reason, action, target_table, target, before, after)
    VALUES (terms_current_source(),
            terms_current_actor(),
            NULLIF(current_setting('terms.request_id', true), ''),
            NULLIF(current_setting('terms.reason', true), ''),
            lower(TG_OP),
            TG_TABLE_NAME,
            v_target,
            CASE WHEN TG_OP <> 'INSERT' THEN to_jsonb(OLD) - 'id' END,
            CASE WHEN TG_OP <> 'DELETE' THEN to_jsonb(NEW) - 'id' END);
    RETURN NULL;
END
$$;

CREATE TRIGGER code_system_version_audit
    AFTER INSERT OR UPDATE OR DELETE ON code_system_version
    FOR EACH ROW EXECUTE FUNCTION audit_capture('code_system_id', 'version', 'source_sha256');

CREATE TRIGGER code_system_enablement_audit
    AFTER INSERT OR UPDATE OR DELETE ON code_system_enablement
    FOR EACH ROW EXECUTE FUNCTION audit_capture('code_system_id');

-- Written by the authz interceptor for a denied RPC (outcome = 'denied').
CREATE FUNCTION record_denied_attempt(p_actor jsonb, p_request_id text, p_rpc text, p_reason text)
    RETURNS void
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public, pg_temp AS $$
INSERT INTO terms_audit_event (source, actor, request_id, reason, action, target_table, target, outcome)
VALUES ('api', p_actor, p_request_id, p_reason, 'rpc', 'rpc', jsonb_build_object('rpc', p_rpc), 'denied')
$$;

-- activate_version as in 001, plus activated_at/activated_by and the activation log.
CREATE OR REPLACE FUNCTION activate_version(p_version_id uuid)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
    v_status         code_system_status;
    v_load_status    load_status;
    v_validity       daterange;
    v_before         daterange;
    v_previous       uuid;
BEGIN
    SELECT code_system_id, status, load_status, validity
    INTO v_code_system_id, v_status, v_load_status, v_validity
    FROM code_system_version
    WHERE id = p_version_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'code_system_version % does not exist', p_version_id;
    END IF;

    IF v_load_status <> 'ready' THEN
        RAISE EXCEPTION 'code_system_version % has load_status %; only ready versions can be activated',
            p_version_id, v_load_status;
    END IF;

    IF v_status = 'retired' THEN
        RAISE EXCEPTION 'code_system_version % is retired', p_version_id;
    END IF;

    IF v_status = 'active' THEN
        RETURN;
    END IF;

    UPDATE code_system_version
    SET status = 'superseded'
    WHERE code_system_id = v_code_system_id
      AND status = 'active'
      AND id <> p_version_id
    RETURNING id INTO v_previous;

    IF v_validity IS NOT NULL THEN
        v_before := CASE WHEN lower_inf(v_validity) THEN 'empty'::daterange
                         ELSE daterange(NULL, lower(v_validity), '[)') END;

        UPDATE code_system_version
        SET status = 'retired'
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_validity
          AND isempty(validity * v_before);

        UPDATE code_system_version
        SET validity = validity * v_before
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_validity;
    END IF;

    UPDATE code_system_version
    SET status = 'active', activated_at = clock_timestamp(), activated_by = terms_current_actor()
    WHERE id = p_version_id;

    INSERT INTO version_activation_log (code_system_id, from_version_id, to_version_id, action, actor, request_id, reason)
    VALUES (v_code_system_id, v_previous, p_version_id, 'activate', terms_current_actor(),
            NULLIF(current_setting('terms.request_id', true), ''),
            NULLIF(current_setting('terms.reason', true), ''));
END
$$;


---- create above / drop below ----


CREATE OR REPLACE FUNCTION activate_version(p_version_id uuid)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
    v_status         code_system_status;
    v_load_status    load_status;
    v_validity       daterange;
    v_before         daterange;
BEGIN
    SELECT code_system_id, status, load_status, validity
    INTO v_code_system_id, v_status, v_load_status, v_validity
    FROM code_system_version
    WHERE id = p_version_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'code_system_version % does not exist', p_version_id;
    END IF;

    IF v_load_status <> 'ready' THEN
        RAISE EXCEPTION 'code_system_version % has load_status %; only ready versions can be activated',
            p_version_id, v_load_status;
    END IF;

    IF v_status = 'retired' THEN
        RAISE EXCEPTION 'code_system_version % is retired', p_version_id;
    END IF;

    IF v_status = 'active' THEN
        RETURN;
    END IF;

    UPDATE code_system_version
    SET status = 'superseded'
    WHERE code_system_id = v_code_system_id
      AND status = 'active'
      AND id <> p_version_id;

    IF v_validity IS NOT NULL THEN
        -- The part of the timeline before the new range starts; empty if it starts at -infinity.
        v_before := CASE WHEN lower_inf(v_validity) THEN 'empty'::daterange
                         ELSE daterange(NULL, lower(v_validity), '[)') END;

        UPDATE code_system_version
        SET status = 'retired'
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_validity
          AND isempty(validity * v_before);

        UPDATE code_system_version
        SET validity = validity * v_before
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_validity;
    END IF;

    UPDATE code_system_version
    SET status = 'active'
    WHERE id = p_version_id;
END
$$;

DROP FUNCTION record_denied_attempt(jsonb, text, text, text);
DROP TRIGGER code_system_enablement_audit ON code_system_enablement;
DROP TRIGGER code_system_version_audit ON code_system_version;
DROP FUNCTION audit_capture();
DROP TABLE terms_audit_event;
DROP FUNCTION terms_audit_event_append_only();
DROP TABLE version_activation_log;
DROP TYPE version_activation_action;
DROP FUNCTION terms_current_source();
DROP FUNCTION terms_current_actor();
DROP TRIGGER code_system_version_identity ON code_system_version;
DROP FUNCTION code_system_version_identity_immutable();
ALTER TABLE code_system_version
    DROP CONSTRAINT code_system_version_source_sha256_required,
    DROP COLUMN activated_by,
    DROP COLUMN activated_at,
    DROP COLUMN validated_at,
    DROP COLUMN source_sha256;
