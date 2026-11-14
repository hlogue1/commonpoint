-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T3: a date-of-service rollback couldn't be undone. Activating ICD-10-CM 2027-04 trimmed 2027's
-- validity for good, so re-activating 2027 left May 2027 resolving to the April update.
--
-- * published_validity is the range the publisher released the version for. It is set once, at
--   insert (defaulting to validity), and is immutable. validity stays the effective range, which
--   activation may trim, and is always inside published_validity.
-- * activate_version() activates the target over its published range: it trims or retires the
--   other active/superseded versions against that range (as before), then restores the target's
--   validity from published_validity. Re-activating a version therefore undoes earlier trims.
-- * rollback_version(code_system_id) undoes the most recent activation: the active version goes
--   back to 'staged' and the version it replaced (from version_activation_log) is re-activated.
--   Rolling back again undoes the activation before that, if there was one.
-- * Activations lock the code_system row, so two concurrent activations for one system
--   serialize instead of one failing on code_system_version_one_active (review B4).
--
-- Rows that existed before this migration get published_validity = their current validity; a
-- range that had already been trimmed can't be recovered here.

ALTER TABLE code_system_version ADD COLUMN published_validity daterange;

-- The backfill updates every row; rows from before 016 may lack source_sha256, which the NOT
-- VALID check would reject on update. Lift it for the backfill and put it back unchanged.
ALTER TABLE code_system_version DROP CONSTRAINT code_system_version_source_sha256_required;
UPDATE code_system_version SET published_validity = validity WHERE validity IS NOT NULL;
ALTER TABLE code_system_version
    ADD CONSTRAINT code_system_version_source_sha256_required CHECK (source_sha256 IS NOT NULL) NOT VALID;

ALTER TABLE code_system_version
    ADD CONSTRAINT code_system_version_published_validity CHECK (
        (validity IS NULL) = (published_validity IS NULL)
        AND (validity IS NULL OR validity <@ published_validity));

CREATE FUNCTION code_system_version_published_validity()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        NEW.published_validity := COALESCE(NEW.published_validity, NEW.validity);
    ELSIF NEW.published_validity IS DISTINCT FROM OLD.published_validity THEN
        RAISE EXCEPTION 'code_system_version %: published_validity is immutable', OLD.id;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER code_system_version_published
    BEFORE INSERT OR UPDATE ON code_system_version
    FOR EACH ROW EXECUTE FUNCTION code_system_version_published_validity();

-- Shared by activate_version and rollback_version. p_from overrides the logged from_version_id
-- (rollback stages the current version before calling this, so there is no active one to find).
CREATE FUNCTION terms_activate(p_version_id uuid, p_action version_activation_action, p_from uuid DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
    v_status         code_system_status;
    v_load_status    load_status;
    v_published      daterange;
    v_before         daterange;
    v_previous       uuid;
BEGIN
    SELECT code_system_id INTO v_code_system_id FROM code_system_version WHERE id = p_version_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'code_system_version % does not exist', p_version_id;
    END IF;
    PERFORM 1 FROM code_system WHERE id = v_code_system_id FOR UPDATE;

    SELECT status, load_status, published_validity
    INTO v_status, v_load_status, v_published
    FROM code_system_version
    WHERE id = p_version_id
    FOR UPDATE;

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

    IF v_published IS NOT NULL THEN
        -- The part of the timeline before the target's range starts; empty if it starts at -infinity.
        v_before := CASE WHEN lower_inf(v_published) THEN 'empty'::daterange
                         ELSE daterange(NULL, lower(v_published), '[)') END;

        UPDATE code_system_version
        SET status = 'retired'
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_published
          AND isempty(validity * v_before);

        UPDATE code_system_version
        SET validity = validity * v_before
        WHERE code_system_id = v_code_system_id
          AND id <> p_version_id
          AND status IN ('active', 'superseded')
          AND validity && v_published;
    END IF;

    UPDATE code_system_version
    SET status       = 'active',
        validity     = published_validity,
        activated_at = clock_timestamp(),
        activated_by = terms_current_actor()
    WHERE id = p_version_id;

    INSERT INTO version_activation_log (code_system_id, from_version_id, to_version_id, action, actor, request_id, reason)
    VALUES (v_code_system_id, COALESCE(p_from, v_previous), p_version_id, p_action, terms_current_actor(),
            NULLIF(current_setting('terms.request_id', true), ''),
            NULLIF(current_setting('terms.reason', true), ''));
END
$$;

-- For a dated version, any other active or superseded version whose range overlaps the target's
-- published range is cut back to end where that range starts; one with nothing left before
-- that point is retired. Re-activating an older version therefore retires newer ones that start
-- after it. To undo an activation without retiring anything, use rollback_version.
CREATE OR REPLACE FUNCTION activate_version(p_version_id uuid)
    RETURNS void
    LANGUAGE plpgsql AS $$
BEGIN
    PERFORM terms_activate(p_version_id, 'activate');
END
$$;

CREATE FUNCTION rollback_version(p_code_system_id CITEXT)
    RETURNS uuid
    LANGUAGE plpgsql AS $$
DECLARE
    v_current  uuid;
    v_previous uuid;
BEGIN
    PERFORM 1 FROM code_system WHERE id = p_code_system_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'code system % does not exist', p_code_system_id;
    END IF;

    SELECT id INTO v_current
    FROM code_system_version
    WHERE code_system_id = p_code_system_id AND status = 'active';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'code system % has no active version to roll back', p_code_system_id;
    END IF;

    SELECT from_version_id INTO v_previous
    FROM version_activation_log
    WHERE to_version_id = v_current AND action = 'activate'
    ORDER BY at DESC, id DESC
    LIMIT 1;
    IF v_previous IS NULL THEN
        RAISE EXCEPTION 'code system %: no version was active before %, nothing to roll back to',
            p_code_system_id, v_current;
    END IF;

    UPDATE code_system_version SET status = 'staged' WHERE id = v_current;
    PERFORM terms_activate(v_previous, 'rollback', v_current);
    RETURN v_previous;
END
$$;


---- create above / drop below ----


DROP FUNCTION rollback_version(citext);

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

DROP FUNCTION terms_activate(uuid, version_activation_action, uuid);
DROP TRIGGER code_system_version_published ON code_system_version;
DROP FUNCTION code_system_version_published_validity();
ALTER TABLE code_system_version
    DROP CONSTRAINT code_system_version_published_validity,
    DROP COLUMN published_validity;
