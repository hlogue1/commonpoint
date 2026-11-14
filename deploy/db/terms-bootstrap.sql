-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Cluster-level setup for the terminology database (finding T6 in docs/PLAN.md). Run once per
-- PostgreSQL cluster as a superuser, before the first tern migration. It is idempotent.
-- Roles are cluster-wide, so they can't be created by a per-database tern migration.
--
--   cp_terms_migrations  runs tern (deploy/db/tern.conf); owns control objects
--   cp_terms_import      the loader; owns the content tables and their partitions
--   cp_terms_app         cmd/terms; SELECT on content, changes versions only through functions
--
-- No passwords live in the repo. Set them out of band, e.g.
--   ALTER ROLE cp_terms_app PASSWORD '...';
--
-- Then create the database with the migrations role as owner:
--   CREATE DATABASE commonpoint_terms OWNER cp_terms_migrations;
--
-- If migrations 001-019 were applied by a different role, grant that role membership in
-- cp_terms_migrations (GRANT cp_terms_migrations TO <that role>) before applying 020, and
-- point tern.conf at cp_terms_migrations afterwards.

DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cp_terms_migrations') THEN
        CREATE ROLE cp_terms_migrations LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cp_terms_import') THEN
        CREATE ROLE cp_terms_import LOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'cp_terms_app') THEN
        CREATE ROLE cp_terms_app LOGIN;
    END IF;
    -- Content tables are owned by cp_terms_import (ATTACH/DETACH need ownership of the parent);
    -- membership lets later migrations alter them.
    IF NOT EXISTS (SELECT FROM pg_auth_members m
                   WHERE m.roleid = 'cp_terms_import'::regrole AND m.member = 'cp_terms_migrations'::regrole) THEN
        GRANT cp_terms_import TO cp_terms_migrations;
    END IF;
END
$$;
