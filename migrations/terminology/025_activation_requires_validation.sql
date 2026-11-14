-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review B4 (remaining part): activation requires a passing validation. `ctl terms validate`
-- (ValidateVersion, M3) sets code_system_version.validated_at, which the import role may update;
-- activate_version and rollback_version refuse a version without it. Versions already active
-- are unaffected until something re-activates them.

CREATE OR REPLACE FUNCTION terms_activate(p_version_id uuid, p_action version_activation_action, p_from uuid DEFAULT NULL)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
    v_status         code_system_status;
    v_load_status    load_status;
    v_published      daterange;
    v_validated_at   timestamptz;
    v_before         daterange;
    v_previous       uuid;
BEGIN
    SELECT code_system_id INTO v_code_system_id FROM code_system_version WHERE id = p_version_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'code_system_version % does not exist', p_version_id;
    END IF;
    PERFORM 1 FROM code_system WHERE id = v_code_system_id FOR UPDATE;

    SELECT status, load_status, published_validity, validated_at
    INTO v_status, v_load_status, v_published, v_validated_at
    FROM code_system_version
    WHERE id = p_version_id
    FOR UPDATE;

    IF v_load_status <> 'ready' THEN
        RAISE EXCEPTION 'code_system_version % has load_status %; only ready versions can be activated',
            p_version_id, v_load_status;
    END IF;

    IF v_validated_at IS NULL THEN
        RAISE EXCEPTION 'code_system_version % has not passed validation (ctl terms validate); only validated versions can be activated',
            p_version_id;
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


---- create above / drop below ----


CREATE OR REPLACE FUNCTION terms_activate(p_version_id uuid, p_action version_activation_action, p_from uuid DEFAULT NULL)
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
