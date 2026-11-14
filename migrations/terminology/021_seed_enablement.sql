-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T7: code_system_enablement was never seeded, so lookup() returned nothing for any system.
-- Every code system gets a row: open-tier systems enabled, restricted tiers disabled until an
-- operator enables them with a license_reference (rule 11). The trigger enforces that.

CREATE FUNCTION code_system_enablement_check_license()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    v_tier CITEXT;
BEGIN
    IF NEW.enabled THEN
        SELECT license_tier_id INTO v_tier FROM code_system WHERE id = NEW.code_system_id;
        IF v_tier <> 'open' AND COALESCE(btrim(NEW.license_reference), '') = '' THEN
            RAISE EXCEPTION 'code system % has license tier %; enabling it requires a license_reference',
                NEW.code_system_id, v_tier;
        END IF;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER code_system_enablement_license
    BEFORE INSERT OR UPDATE ON code_system_enablement
    FOR EACH ROW EXECUTE FUNCTION code_system_enablement_check_license();

INSERT INTO code_system_enablement (code_system_id, enabled)
SELECT id, license_tier_id = 'open'
FROM code_system
ORDER BY id
ON CONFLICT (code_system_id) DO NOTHING;


---- create above / drop below ----


DELETE FROM code_system_enablement WHERE license_reference IS NULL;
DROP TRIGGER code_system_enablement_license ON code_system_enablement;
DROP FUNCTION code_system_enablement_check_license();
