-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- T4 (review C5): version_for_date(citext, date) and version_for_date(text, date) were overloads,
-- and an untyped literal ('icd10cm') picked the URI one and silently returned NULL. They become
-- two distinct names. validate_code() switches to the id variant.
--
-- A version with no validity range is not tied to dates of service, so it answers for any date
-- while it is the active version.

CREATE FUNCTION version_for_date_by_id(p_code_system_id CITEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT v.id
FROM code_system_version v
WHERE v.code_system_id = p_code_system_id
  AND v.status IN ('active', 'superseded')
  AND (v.validity @> p_date OR (v.validity IS NULL AND v.status = 'active'))
  AND v.load_status = 'ready'
ORDER BY (v.status = 'active') DESC, lower(v.validity) DESC
LIMIT 1
$$;

CREATE FUNCTION version_for_date_by_uri(p_uri TEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT version_for_date_by_id(cs.id, p_date)
FROM code_system cs
WHERE cs.uri = p_uri
$$;

CREATE OR REPLACE FUNCTION validate_code(p_code_system text, p_code text, p_date date DEFAULT current_date)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM concept_index ci
    WHERE ci.code_system = p_code_system::citext
      AND ci.code = p_code
      AND ci.active
      AND ci.version_id = version_for_date_by_id(p_code_system::citext, p_date))
$$;

DROP FUNCTION version_for_date(text, date);
DROP FUNCTION version_for_date(citext, date);


---- create above / drop below ----


CREATE FUNCTION version_for_date(p_code_system_id CITEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT v.id
FROM code_system_version v
WHERE v.code_system_id = p_code_system_id
  AND v.status IN ('active', 'superseded')
  AND (v.validity @> p_date OR (v.validity IS NULL AND v.status = 'active'))
  AND v.load_status = 'ready'
ORDER BY (v.status = 'active') DESC, lower(v.validity) DESC
LIMIT 1
$$;

CREATE FUNCTION version_for_date(p_uri TEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT version_for_date(cs.id, p_date)
FROM code_system cs
WHERE cs.uri = p_uri
$$;

CREATE OR REPLACE FUNCTION validate_code(p_code_system text, p_code text, p_date date DEFAULT current_date)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM concept_index ci
    WHERE ci.code_system = p_code_system::citext
      AND ci.code = p_code
      AND ci.active
      AND ci.version_id = version_for_date(p_code_system::citext, p_date))
$$;

DROP FUNCTION version_for_date_by_uri(text, date);
DROP FUNCTION version_for_date_by_id(citext, date);
