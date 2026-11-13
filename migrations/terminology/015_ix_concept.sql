CREATE VIEW concept_index AS
    SELECT x.code_system, x.version_id, x.code, x.display, x.active
    FROM (
             -- core clinical
             SELECT 'snomed'::citext AS code_system, version_id, id::text AS code, preferred_term_en_us AS display, active FROM snomed_concept
             UNION ALL SELECT 'loinc',    version_id, loinc_num, long_common_name, status IN ('active', 'trial') FROM loinc_term
             -- drugs
             UNION ALL SELECT 'rxnorm',   version_id, rxcui, name, active FROM rxnorm_concept
             UNION ALL SELECT 'medrt',    version_id, nui, name, true FROM medrt_concept
             UNION ALL SELECT 'atc',      version_id, code, name, true FROM atc_code
             UNION ALL SELECT 'cms_frf',  version_id, rxcui, name, true FROM cms_frf_drug
             UNION ALL SELECT 'uspmg',    version_id, code, name, true FROM uspmg_class
             -- billing and payer
             UNION ALL SELECT 'icd10cm',  version_id, code, long_desc, true FROM icd10_code
             UNION ALL SELECT 'icd10pcs', version_id, code, long_desc, true FROM icd_pcs_code
             UNION ALL SELECT 'cpt',      version_id, code, long_descriptor, true FROM cpt_code
             -- Active is judged against the release's own start, not the clock, so a release always gives the same answer.
             UNION ALL SELECT 'hcpcs',    hc.version_id, hc.code, hc.long_desc,
                              COALESCE(upper_inf(hc.validity) OR upper(hc.validity) > COALESCE(lower(rv.validity), rv.release_date), true)
                       FROM hcpcs_code hc JOIN code_system_version rv ON rv.id = hc.version_id
             UNION ALL SELECT 'cdt',      version_id, code, nomenclature, true FROM cdt_code
             UNION ALL SELECT 'icd9cm',   version_id, code, long_desc, true FROM icd9_code
             UNION ALL SELECT 'abc',      version_id, code, descriptor, true FROM abc_code
             UNION ALL SELECT 'sop',      version_id, code, display, true FROM sop_code
             -- reference
             UNION ALL SELECT 'cvx',      version_id, code, full_name, status = 'active' FROM cvx_vaccine
             UNION ALL SELECT 'mvx',      version_id, code, name, active FROM mvx_manufacturer
             UNION ALL SELECT 'nucc',     version_id, code, COALESCE(display_name, specialization, classification), true FROM nucc_taxonomy
             UNION ALL SELECT 'cdc_race_ethnicity', version_id, code, display, true FROM cdc_race_ethnicity_code
             UNION ALL SELECT 'ucum',     version_id, code, display, true FROM ucum_common_unit
             -- analytics groupers
             UNION ALL SELECT 'ccsr_dx',  version_id, code, description, true FROM ccsr_dx_category
             UNION ALL SELECT 'ccsr_pr',  version_id, code, description, true FROM ccsr_proc_category
             UNION ALL SELECT 'ccs',      version_id, kind || ':' || code, label, true FROM ccs_category
             UNION ALL SELECT 'ccs_ml',   version_id, kind || ':' || code, label, true FROM ccs_ml_category
             -- nursing
             UNION ALL SELECT 'nanda',    version_id, code, label, true FROM nanda_diagnosis
             UNION ALL SELECT 'nic',      version_id, code, label, true FROM nic_intervention
             UNION ALL SELECT 'noc',      version_id, code, label, true FROM noc_outcome
             UNION ALL SELECT 'omaha',    version_id, code, name, true FROM omaha_concept
             UNION ALL SELECT 'pnds',     version_id, code, label, true FROM pnds_concept
             -- international
             UNION ALL SELECT 'icpc2',    version_id, code, title, true FROM icpc2_code
             UNION ALL SELECT 'icpc2plus', version_id, code, label, true FROM icpc2plus_term
             UNION ALL SELECT 'icpc2_icd10', version_id, term_id, term, true FROM icpc2_icd10_term
             UNION ALL SELECT 'icf',      version_id, code, title, true FROM icf_code
             -- genomics, rare disease, oncology
             UNION ALL SELECT 'hgnc',     version_id, hgnc_id, symbol, status = 'approved' FROM hgnc_gene
             UNION ALL SELECT 'hpo',      version_id, id, name, NOT obsolete FROM hpo_term
             UNION ALL SELECT 'mondo',    version_id, id, name, NOT obsolete FROM mondo_term
             UNION ALL SELECT 'orphanet', version_id, code, name, true FROM orphanet_disorder
             UNION ALL SELECT 'ncit',     version_id, code, preferred_name, NOT retired FROM ncit_concept
             UNION ALL SELECT 'pdq',      version_id, cdr_id, name, true FROM pdq_term
             -- regulatory and devices
             UNION ALL SELECT 'meddra',   version_id, code, name, true FROM meddra_term
             UNION ALL SELECT 'meddra',   version_id, code, name, current FROM meddra_llt WHERE code <> pt_code  -- PT-level LLTs are already above
             UNION ALL SELECT 'umdns',    version_id, code, name, active FROM umdns_category
             -- consumer health
             UNION ALL SELECT 'chv',      version_id, code, term, true FROM chv_term
             UNION ALL SELECT 'medlineplus', version_id, topic_id, title, true FROM medlineplus_topic
         ) x
             JOIN code_system_enablement e ON e.code_system_id = x.code_system AND e.enabled
             JOIN code_system_version v ON v.id = x.version_id AND v.load_status = 'ready';

-- Parameters are text, not citext: text has no implicit cast to citext, so a
-- citext parameter would reject ordinary text arguments (e.g. a Rust String).
-- The cast inside keeps comparisons case-insensitive.

-- $lookup against the active release.
CREATE FUNCTION lookup(p_code_system text, p_code text)
    RETURNS TABLE (version_id uuid, display text, active boolean)
    LANGUAGE sql STABLE AS $$
SELECT ci.version_id, ci.display, ci.active
FROM concept_index ci
WHERE ci.code_system = p_code_system::citext
  AND ci.code = p_code
  AND ci.version_id = (SELECT av.version_id FROM active_version av
                       WHERE av.code_system_id = p_code_system::citext)
$$;

-- $validate-code for a date: is the code present and active in the release in
-- effect on that date? (Billing systems pass the date of service.)
-- The citext cast selects the code-system-id overload of version_for_date; a text
-- argument would select the URI overload and never match.
CREATE FUNCTION validate_code(p_code_system text, p_code text, p_date date DEFAULT current_date)
    RETURNS boolean
    LANGUAGE sql STABLE AS $$
SELECT EXISTS (
    SELECT 1 FROM concept_index ci
    WHERE ci.code_system = p_code_system::citext
      AND ci.code = p_code
      AND ci.active
      AND ci.version_id = version_for_date(p_code_system::citext, p_date))
$$;