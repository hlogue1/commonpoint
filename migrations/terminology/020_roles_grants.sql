-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T6: roles and grants. The roles themselves are cluster-wide and created by
-- deploy/db/terms-bootstrap.sql; this migration only assigns ownership and privileges.
--
--   cp_terms_migrations  runs tern; owns the control objects (code_system_version, audit, ...)
--   cp_terms_import      owns every content table: all partitioned tables, their partitions and
--                        the <system>_release tables (ATTACH/DETACH need ownership of the parent).
--                        INSERT/DELETE on the unpartitioned content tables; TRUNCATE is revoked even
--                        on the tables it owns.
--                        Registers versions and records load/validation progress.
--   cp_terms_app         SELECT only. Versions and enablement change only through the
--                        SECURITY DEFINER functions activate_version, rollback_version and
--                        set_enablement; denied RPCs are recorded via record_denied_attempt.
--
-- Partition lifecycle and retire order: docs/terms/partition-lifecycle.md.

DO $$
BEGIN
    IF (SELECT count(*) FROM pg_roles
        WHERE rolname IN ('cp_terms_migrations', 'cp_terms_import', 'cp_terms_app')) <> 3 THEN
        RAISE EXCEPTION 'cp_terms_* roles are missing; run deploy/db/terms-bootstrap.sql as a superuser first';
    END IF;
END
$$;

GRANT USAGE ON SCHEMA public TO cp_terms_import, cp_terms_app;
GRANT CREATE ON SCHEMA public TO cp_terms_import;

-- Content tables move to the import role.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.oid::regclass AS rel
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND (c.relkind = 'p' OR c.relispartition OR (c.relkind = 'r' AND c.relname LIKE '%\_release'))
        ORDER BY c.relname
    LOOP
        EXECUTE format('ALTER TABLE %s OWNER TO cp_terms_import', r.rel);
        -- Retiring is DETACH + DROP, never TRUNCATE of a parent (which would empty every version).
        -- UPDATE can't be revoked from the owner: foreign-key checks lock referenced rows
        -- FOR KEY SHARE as the referenced table's owner, which needs it. "Never UPDATE content"
        -- (rule 2) is enforced in code.
        EXECUTE format('REVOKE TRUNCATE ON %s FROM cp_terms_import', r.rel);
    END LOOP;
END
$$;

GRANT SELECT ON ALL TABLES IN SCHEMA public TO cp_terms_import, cp_terms_app;

-- Unpartitioned content (small systems): load and retire by version.
DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.oid::regclass AS rel
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relispartition
          AND c.relname NOT LIKE '%\_release'
          AND c.relname NOT IN ('license_tier_option', 'code_system', 'code_system_version',
                                'code_system_enablement', 'version_activation_log',
                                'terms_audit_event', 'schema_version')
        ORDER BY c.relname
    LOOP
        EXECUTE format('GRANT INSERT, DELETE ON %s TO cp_terms_import', r.rel);
    END LOOP;
END
$$;

GRANT INSERT, DELETE, UPDATE (load_status, loaded_at, validated_at) ON code_system_version TO cp_terms_import;

-- Tables created later (partitions by the loader, tables by later migrations) are readable too.
ALTER DEFAULT PRIVILEGES FOR ROLE cp_terms_import IN SCHEMA public GRANT SELECT ON TABLES TO cp_terms_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO cp_terms_import, cp_terms_app;

CREATE FUNCTION set_enablement(p_code_system_id CITEXT, p_enabled boolean, p_license_reference text)
    RETURNS void
    LANGUAGE sql
    SECURITY DEFINER
    SET search_path = public, pg_temp AS $$
INSERT INTO code_system_enablement (code_system_id, enabled, license_reference)
VALUES (p_code_system_id, p_enabled, p_license_reference)
ON CONFLICT (code_system_id) DO UPDATE
    SET enabled = excluded.enabled, license_reference = excluded.license_reference
$$;

ALTER FUNCTION activate_version(uuid) SECURITY DEFINER SET search_path = public, pg_temp;
ALTER FUNCTION rollback_version(citext) SECURITY DEFINER SET search_path = public, pg_temp;

REVOKE EXECUTE ON FUNCTION activate_version(uuid), rollback_version(citext), set_enablement(citext, boolean, text),
    record_denied_attempt(jsonb, text, text, text), terms_activate(uuid, version_activation_action, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION activate_version(uuid), rollback_version(citext), set_enablement(citext, boolean, text),
    record_denied_attempt(jsonb, text, text, text) TO cp_terms_app;


---- create above / drop below ----


GRANT EXECUTE ON FUNCTION activate_version(uuid), rollback_version(citext),
    record_denied_attempt(jsonb, text, text, text), terms_activate(uuid, version_activation_action, uuid) TO PUBLIC;
REVOKE EXECUTE ON FUNCTION activate_version(uuid), rollback_version(citext),
    record_denied_attempt(jsonb, text, text, text) FROM cp_terms_app;
ALTER FUNCTION rollback_version(citext) SECURITY INVOKER RESET ALL;
ALTER FUNCTION activate_version(uuid) SECURITY INVOKER RESET ALL;
DROP FUNCTION set_enablement(citext, boolean, text);

ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE SELECT ON TABLES FROM cp_terms_import, cp_terms_app;
ALTER DEFAULT PRIVILEGES FOR ROLE cp_terms_import IN SCHEMA public REVOKE SELECT ON TABLES FROM cp_terms_app;

DO $$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT c.oid::regclass AS rel
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND (c.relkind = 'p' OR c.relispartition OR (c.relkind = 'r' AND c.relname LIKE '%\_release'))
        ORDER BY c.relname
    LOOP
        EXECUTE format('ALTER TABLE %s OWNER TO %I', r.rel, current_user);
        EXECUTE format('GRANT ALL ON %s TO %I', r.rel, current_user);
    END LOOP;
END
$$;

REVOKE ALL ON ALL TABLES IN SCHEMA public FROM cp_terms_import, cp_terms_app;
REVOKE ALL ON SCHEMA public FROM cp_terms_import, cp_terms_app;
