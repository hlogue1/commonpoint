CREATE EXTENSION IF NOT EXISTS citext;
CREATE EXTENSION IF NOT EXISTS plpgsql;
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE license_tier_option (
    id CITEXT NOT NULL PRIMARY KEY
);

INSERT INTO license_tier_option VALUES
                                          ('open'),
                                          ('umls'),
                                          ('ama_cpt'),
                                          ('other_restricted'),
                                          ('ada'),
                                          ('ecri'),
                                          ('who'),
                                          ('meddra_msso'),
                                          ('snomed_affiliate'),
                                          ('nanda_elsevier');

CREATE TABLE code_system
(
    id                        CITEXT PRIMARY KEY NOT NULL,
    uri                       TEXT    NOT NULL UNIQUE,
    name                      TEXT    NOT NULL,
    publisher                 TEXT,
    license_tier_id           CITEXT  NOT NULL REFERENCES license_tier_option(id),
    date_of_service_versioned boolean NOT NULL DEFAULT false
);

-- One row per id pinned by a <system>_release CHECK. uri values starting with
-- urn:commonpoint:cs: are placeholders for systems with no established FHIR/THO URI.
INSERT INTO code_system (id, uri, name, publisher, license_tier_id) VALUES
    ('snomed',             'http://snomed.info/sct',                                   'SNOMED CT',                                  'SNOMED International',   'snomed_affiliate'),
    ('loinc',              'http://loinc.org',                                         'LOINC',                                      'Regenstrief Institute',  'open'),
    ('rxnorm',             'http://www.nlm.nih.gov/research/umls/rxnorm',              'RxNorm',                                     'NLM',                    'open'),
    ('medrt',              'http://va.gov/terminology/medrt',                          'MED-RT',                                     'VA',                     'open'),
    ('atc',                'http://www.whocc.no/atc',                                  'Anatomical Therapeutic Chemical',            'WHO',                    'who'),
    ('cms_frf',            'urn:commonpoint:cs:cms_frf',                               'CMS Formulary Reference File',               'CMS',                    'open'),
    ('uspmg',              'urn:commonpoint:cs:uspmg',                                 'USP Medicare Model Guidelines',              'USP',                    'open'),
    ('icd10cm',            'http://hl7.org/fhir/sid/icd-10-cm',                        'ICD-10-CM',                                  'CDC NCHS',               'open'),
    ('icd10pcs',           'http://www.cms.gov/Medicare/Coding/ICD10',                 'ICD-10-PCS',                                 'CMS',                    'open'),
    ('cpt',                'http://www.ama-assn.org/go/cpt',                           'Current Procedural Terminology',             'AMA',                    'ama_cpt'),
    ('hcpcs',              'http://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets',  'HCPCS Level II',                             'CMS',                    'open'),
    ('cdt',                'http://www.ada.org/cdt',                                   'Code on Dental Procedures and Nomenclature', 'ADA',                    'ada'),
    ('icd9cm',             'http://hl7.org/fhir/sid/icd-9-cm',                         'ICD-9-CM',                                   'CDC NCHS / CMS',         'open'),
    ('abc',                'urn:commonpoint:cs:abc',                                   'ABC Codes',                                  'ABC Coding Solutions',   'other_restricted'),
    ('sop',                'https://nahdo.org/sopt',                                   'Source of Payment Typology',                 'NAHDO',                  'open'),
    ('ncci',               'urn:commonpoint:cs:ncci',                                  'National Correct Coding Initiative',         'CMS',                    'open'),
    ('cvx',                'http://hl7.org/fhir/sid/cvx',                              'CVX Vaccines Administered',                  'CDC',                    'open'),
    ('mvx',                'http://terminology.hl7.org/CodeSystem/MVX',                'MVX Vaccine Manufacturers',                  'CDC',                    'open'),
    ('nucc',               'http://nucc.org/provider-taxonomy',                        'NUCC Health Care Provider Taxonomy',         'NUCC',                   'open'),
    ('cdc_race_ethnicity', 'urn:oid:2.16.840.1.113883.6.238',                          'CDC Race and Ethnicity',                     'CDC',                    'open'),
    ('ucum',               'http://unitsofmeasure.org',                                'UCUM',                                       'Regenstrief Institute',  'open'),
    ('ccsr_dx',            'urn:commonpoint:cs:ccsr_dx',                               'CCSR for ICD-10-CM Diagnoses',               'AHRQ HCUP',              'open'),
    ('ccsr_pr',            'urn:commonpoint:cs:ccsr_pr',                               'CCSR for ICD-10-PCS Procedures',             'AHRQ HCUP',              'open'),
    ('ccs',                'urn:commonpoint:cs:ccs',                                   'Clinical Classifications Software',          'AHRQ HCUP',              'open'),
    ('nanda',              'urn:commonpoint:cs:nanda',                                 'NANDA-I Nursing Diagnoses',                  'NANDA International',    'nanda_elsevier'),
    ('nic',                'urn:commonpoint:cs:nic',                                   'Nursing Interventions Classification',       'Elsevier',               'nanda_elsevier'),
    ('noc',                'urn:commonpoint:cs:noc',                                   'Nursing Outcomes Classification',            'Elsevier',               'nanda_elsevier'),
    ('omaha',              'urn:commonpoint:cs:omaha',                                 'Omaha System',                               'The Omaha System',       'open'),
    ('pnds',               'urn:commonpoint:cs:pnds',                                  'Perioperative Nursing Data Set',             'AORN',                   'other_restricted'),
    ('icpc2',              'http://hl7.org/fhir/sid/icpc-2',                           'ICPC-2',                                     'WONCA',                  'who'),
    ('icpc2plus',          'urn:commonpoint:cs:icpc2plus',                             'ICPC-2 PLUS',                                'University of Sydney',   'who'),
    ('icpc2_icd10',        'urn:commonpoint:cs:icpc2_icd10',                           'ICPC-2 to ICD-10 Thesaurus',                 NULL,                     'who'),
    ('icf',                'urn:commonpoint:cs:icf',                                   'ICF',                                        'WHO',                    'who'),
    ('hgnc',               'http://www.genenames.org',                                 'HGNC Gene Nomenclature',                     'HUGO',                   'open'),
    ('hpo',                'http://human-phenotype-ontology.org',                      'Human Phenotype Ontology',                   'Monarch Initiative',     'open'),
    ('mondo',              'urn:commonpoint:cs:mondo',                                 'Mondo Disease Ontology',                     'Monarch Initiative',     'open'),
    ('orphanet',           'urn:commonpoint:cs:orphanet',                              'Orphanet Rare Disease Nomenclature',         'INSERM',                 'open'),
    ('ncit',               'http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl',       'NCI Thesaurus',                              'NCI',                    'open'),
    ('pdq',                'urn:commonpoint:cs:pdq',                                   'Physician Data Query',                       'NCI',                    'open'),
    ('meddra',             'http://terminology.hl7.org/CodeSystem/mdr',                'MedDRA',                                     'MedDRA MSSO',            'meddra_msso'),
    ('umdns',              'urn:commonpoint:cs:umdns',                                 'Universal Medical Device Nomenclature',      'ECRI',                   'ecri'),
    ('chv',                'urn:commonpoint:cs:chv',                                   'Consumer Health Vocabulary',                 'NLM',                    'open'),
    ('medlineplus',        'urn:commonpoint:cs:medlineplus',                           'MedlinePlus Health Topics',                  'NLM',                    'open'),
    ('umls',               'urn:commonpoint:cs:umls',                                  'UMLS Metathesaurus',                         'NLM',                    'umls');

CREATE TYPE code_system_status AS ENUM ('active', 'staged', 'superseded', 'retired');
CREATE TYPE load_status AS ENUM ('loading', 'ready', 'failed');

CREATE TABLE code_system_version
(
    id               UUID                 DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    code_system_id   CITEXT    NOT NULL REFERENCES code_system (id),
    version          TEXT        NOT NULL,
    fhir_version_uri TEXT,
    release_date     date,
    validity         daterange  NOT NULL,
    status           code_system_status NOT NULL DEFAULT 'staged',
    load_status      load_status NOT NULL DEFAULT 'loading',
    loaded_at        timestamptz,
    UNIQUE (code_system_id, version),
    UNIQUE (id, code_system_id),
    CHECK (NOT isempty(validity)),
    EXCLUDE USING gist (lower(code_system_id::TEXT) WITH =, validity WITH &&) WHERE (status <> 'retired')
);

CREATE UNIQUE INDEX code_system_version_one_active
    ON code_system_version (code_system_id) WHERE status = 'active';

-- code_system_version_one_active cannot be deferred, so the old active version
-- has to be superseded before the new one is activated.
CREATE FUNCTION activate_version(p_version_id uuid)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
BEGIN
    SELECT code_system_id INTO v_code_system_id
    FROM code_system_version
    WHERE id = p_version_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'code_system_version % does not exist', p_version_id;
    END IF;

    UPDATE code_system_version
    SET status = 'superseded'
    WHERE code_system_id = v_code_system_id
      AND status = 'active'
      AND id <> p_version_id;

    UPDATE code_system_version
    SET status = 'active'
    WHERE id = p_version_id;
END
$$;

CREATE TABLE code_system_enablement
(
    code_system_id    CITEXT PRIMARY KEY REFERENCES code_system (id),
    enabled           boolean NOT NULL DEFAULT false,
    license_reference TEXT
);

CREATE VIEW active_version AS
SELECT cs.id AS code_system_id, cs.uri, cs.name, v.id AS version_id, v.version, v.fhir_version_uri
FROM code_system cs
         JOIN code_system_version v ON v.code_system_id = cs.id AND v.status = 'active' AND v.load_status = 'ready';

CREATE FUNCTION version_for_date(p_uri TEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT v.id
FROM code_system cs
         JOIN code_system_version v ON v.code_system_id = cs.id
WHERE cs.uri = p_uri
  AND v.status IN ('active', 'superseded')
  AND v.validity @> p_date
  AND v.load_status = 'ready'
ORDER BY (v.status = 'active') DESC, lower(v.validity) DESC
LIMIT 1
$$;

-- Lookup by code system id. An untyped literal resolves to the (TEXT, date) URI overload
-- above and returns NULL, so callers passing an id must cast it: 'loinc'::CITEXT.
CREATE FUNCTION version_for_date(p_code_system_id CITEXT, p_date date)
    RETURNS UUID
    LANGUAGE sql STABLE AS $$
SELECT v.id
FROM code_system_version v
WHERE v.code_system_id = p_code_system_id
  AND v.status IN ('active', 'superseded')
  AND v.validity @> p_date
  AND v.load_status = 'ready'
ORDER BY (v.status = 'active') DESC, lower(v.validity) DESC
LIMIT 1
$$;