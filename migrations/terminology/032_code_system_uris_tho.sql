-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C14: code_system.uri checked against HL7 Terminology (THO) v7.5.0, External Code
-- Systems (https://terminology.hl7.org/en/external_code_systems.html), on 2026-11-13.
--
-- Corrected: mvx, meddra. Placeholders replaced by their THO URI: mondo, orphanet, icf, nanda,
-- nic, noc, omaha.
-- Matched THO already: snomed, loinc, rxnorm, medrt, atc, icd10cm, icd10pcs, cpt, hcpcs, cdt,
-- icd9cm, sop, cvx, nucc, cdc_race_ethnicity, ucum, icpc2, hgnc, hpo, ncit.
-- Not in THO, so they keep urn:commonpoint:cs: placeholders: cms_frf, uspmg, abc, ncci, ccsr_dx,
-- ccsr_pr, ccs, ccs_ml, pnds, icpc2plus, icpc2_icd10, pdq, umdns, chv, medlineplus, umls.

UPDATE code_system AS cs SET uri = m.uri
FROM (VALUES
    ('mvx',      'http://hl7.org/fhir/sid/mvx'),
    ('meddra',   'https://www.meddra.org'),
    ('mondo',    'http://purl.obolibrary.org/obo/mondo.owl'),
    ('orphanet', 'https://www.orpha.net'),
    ('icf',      'http://hl7.org/fhir/sid/icf'),
    ('nanda',    'http://www.nanda.org/'),
    ('nic',      'https://nursing.uiowa.edu/cncce/nursing-interventions-classification-overview'),
    ('noc',      'http://terminology.hl7.org/CodeSystem/noc'),
    ('omaha',    'http://terminology.hl7.org/CodeSystem/oms')
) AS m (id, uri)
WHERE cs.id = m.id;


---- create above / drop below ----


UPDATE code_system AS cs SET uri = m.uri
FROM (VALUES
    ('mvx',      'http://terminology.hl7.org/CodeSystem/MVX'),
    ('meddra',   'http://terminology.hl7.org/CodeSystem/mdr'),
    ('mondo',    'urn:commonpoint:cs:mondo'),
    ('orphanet', 'urn:commonpoint:cs:orphanet'),
    ('icf',      'urn:commonpoint:cs:icf'),
    ('nanda',    'urn:commonpoint:cs:nanda'),
    ('nic',      'urn:commonpoint:cs:nic'),
    ('noc',      'urn:commonpoint:cs:noc'),
    ('omaha',    'urn:commonpoint:cs:omaha')
) AS m (id, uri)
WHERE cs.id = m.id;
