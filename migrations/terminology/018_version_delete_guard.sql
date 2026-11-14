-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T2: DELETE FROM code_system_version used to cascade through <system>_release into every
-- partitioned family, deleting content row by row (millions for a real edition) and leaving the
-- emptied partitions attached. Refuse it while any partition for the version exists; retire the
-- partitions first (DETACH + DROP per table, docs/terms/partition-lifecycle.md), which is what
-- `ctl terms clean` does. Unpartitioned small systems still retire by deleting the version (or
-- its *_release row), which cascades.

CREATE FUNCTION code_system_version_refuse_delete_with_partitions()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    v_partition regclass;
BEGIN
    SELECT c.oid::regclass INTO v_partition
    FROM pg_class c
    WHERE c.relispartition
      AND pg_get_expr(c.relpartbound, c.oid) = format('FOR VALUES IN (%L)', OLD.id)
    ORDER BY c.relname
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION 'code_system_version % (% %) still has partitions (e.g. %); retire it via ctl terms clean',
            OLD.id, OLD.code_system_id, OLD.version, v_partition;
    END IF;
    RETURN OLD;
END
$$;

CREATE TRIGGER code_system_version_delete_guard
    BEFORE DELETE ON code_system_version
    FOR EACH ROW EXECUTE FUNCTION code_system_version_refuse_delete_with_partitions();


---- create above / drop below ----


DROP TRIGGER code_system_version_delete_guard ON code_system_version;
DROP FUNCTION code_system_version_refuse_delete_with_partitions();
