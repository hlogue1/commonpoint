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
                                          ('snomed_affiliate'),  -- SNOMED outside member countries; US Edition use is covered by 'umls'
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
INSERT INTO code_system (id, uri, name, publisher, license_tier_id, date_of_service_versioned) VALUES
    ('snomed',             'http://snomed.info/sct',                                   'SNOMED CT',                                  'SNOMED International',   'umls',              false),
    ('loinc',              'http://loinc.org',                                         'LOINC',                                      'Regenstrief Institute',  'open',              false),
    ('rxnorm',             'http://www.nlm.nih.gov/research/umls/rxnorm',              'RxNorm',                                     'NLM',                    'umls',              false),
    ('medrt',              'http://va.gov/terminology/medrt',                          'MED-RT',                                     'VA',                     'open',              false),
    ('atc',                'http://www.whocc.no/atc',                                  'Anatomical Therapeutic Chemical',            'WHO',                    'who',               false),
    ('cms_frf',            'urn:commonpoint:cs:cms_frf',                               'CMS Formulary Reference File',               'CMS',                    'open',              false),
    ('uspmg',              'urn:commonpoint:cs:uspmg',                                 'USP Medicare Model Guidelines',              'USP',                    'open',              false),
    ('icd10cm',            'http://hl7.org/fhir/sid/icd-10-cm',                        'ICD-10-CM',                                  'CDC NCHS',               'open',              true),
    ('icd10pcs',           'http://www.cms.gov/Medicare/Coding/ICD10',                 'ICD-10-PCS',                                 'CMS',                    'open',              true),
    ('cpt',                'http://www.ama-assn.org/go/cpt',                           'Current Procedural Terminology',             'AMA',                    'ama_cpt',           true),
    ('hcpcs',              'http://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets',  'HCPCS Level II',                             'CMS',                    'open',              true),
    ('cdt',                'http://www.ada.org/cdt',                                   'Code on Dental Procedures and Nomenclature', 'ADA',                    'ada',               true),
    ('icd9cm',             'http://hl7.org/fhir/sid/icd-9-cm',                         'ICD-9-CM',                                   'CDC NCHS / CMS',         'open',              false),
    ('abc',                'urn:commonpoint:cs:abc',                                   'ABC Codes',                                  'ABC Coding Solutions',   'other_restricted',  false),
    ('sop',                'https://nahdo.org/sopt',                                   'Source of Payment Typology',                 'NAHDO',                  'open',              false),
    ('ncci',               'urn:commonpoint:cs:ncci',                                  'National Correct Coding Initiative',         'CMS',                    'open',              true),
    ('cvx',                'http://hl7.org/fhir/sid/cvx',                              'CVX Vaccines Administered',                  'CDC',                    'open',              false),
    ('mvx',                'http://terminology.hl7.org/CodeSystem/MVX',                'MVX Vaccine Manufacturers',                  'CDC',                    'open',              false),
    ('nucc',               'http://nucc.org/provider-taxonomy',                        'NUCC Health Care Provider Taxonomy',         'NUCC',                   'open',              false),
    ('cdc_race_ethnicity', 'urn:oid:2.16.840.1.113883.6.238',                          'CDC Race and Ethnicity',                     'CDC',                    'open',              false),
    ('ucum',               'http://unitsofmeasure.org',                                'UCUM',                                       'Regenstrief Institute',  'open',              false),
    ('ccsr_dx',            'urn:commonpoint:cs:ccsr_dx',                               'CCSR for ICD-10-CM Diagnoses',               'AHRQ HCUP',              'open',              false),
    ('ccsr_pr',            'urn:commonpoint:cs:ccsr_pr',                               'CCSR for ICD-10-PCS Procedures',             'AHRQ HCUP',              'open',              false),
    ('ccs',                'urn:commonpoint:cs:ccs',                                   'Clinical Classifications Software (single-level)', 'AHRQ HCUP',              'open',              false),
    ('ccs_ml',             'urn:commonpoint:cs:ccs_ml',                                'Clinical Classifications Software (multi-level)',  'AHRQ HCUP',              'open',              false),
    ('nanda',              'urn:commonpoint:cs:nanda',                                 'NANDA-I Nursing Diagnoses',                  'NANDA International',    'nanda_elsevier',    false),
    ('nic',                'urn:commonpoint:cs:nic',                                   'Nursing Interventions Classification',       'Elsevier',               'nanda_elsevier',    false),
    ('noc',                'urn:commonpoint:cs:noc',                                   'Nursing Outcomes Classification',            'Elsevier',               'nanda_elsevier',    false),
    ('omaha',              'urn:commonpoint:cs:omaha',                                 'Omaha System',                               'The Omaha System',       'open',              false),
    ('pnds',               'urn:commonpoint:cs:pnds',                                  'Perioperative Nursing Data Set',             'AORN',                   'other_restricted',  false),
    ('icpc2',              'http://hl7.org/fhir/sid/icpc-2',                           'ICPC-2',                                     'WONCA',                  'who',               false),
    ('icpc2plus',          'urn:commonpoint:cs:icpc2plus',                             'ICPC-2 PLUS',                                'University of Sydney',   'who',               false),
    ('icpc2_icd10',        'urn:commonpoint:cs:icpc2_icd10',                           'ICPC-2 to ICD-10 Thesaurus',                 NULL,                     'who',               false),
    ('icf',                'urn:commonpoint:cs:icf',                                   'ICF',                                        'WHO',                    'who',               false),
    ('hgnc',               'http://www.genenames.org',                                 'HGNC Gene Nomenclature',                     'HUGO',                   'open',              false),
    ('hpo',                'http://human-phenotype-ontology.org',                      'Human Phenotype Ontology',                   'Monarch Initiative',     'open',              false),
    ('mondo',              'urn:commonpoint:cs:mondo',                                 'Mondo Disease Ontology',                     'Monarch Initiative',     'open',              false),
    ('orphanet',           'urn:commonpoint:cs:orphanet',                              'Orphanet Rare Disease Nomenclature',         'INSERM',                 'open',              false),
    ('ncit',               'http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl',       'NCI Thesaurus',                              'NCI',                    'open',              false),
    ('pdq',                'urn:commonpoint:cs:pdq',                                   'Physician Data Query',                       'NCI',                    'open',              false),
    ('meddra',             'http://terminology.hl7.org/CodeSystem/mdr',                'MedDRA',                                     'MedDRA MSSO',            'meddra_msso',       false),
    ('umdns',              'urn:commonpoint:cs:umdns',                                 'Universal Medical Device Nomenclature',      'ECRI',                   'ecri',              false),
    ('chv',                'urn:commonpoint:cs:chv',                                   'Consumer Health Vocabulary',                 'NLM',                    'open',              false),
    ('medlineplus',        'urn:commonpoint:cs:medlineplus',                           'MedlinePlus Health Topics',                  'NLM',                    'open',              false),
    ('umls',               'urn:commonpoint:cs:umls',                                  'UMLS Metathesaurus',                         'NLM',                    'umls',              false);

CREATE TYPE code_system_status AS ENUM ('active', 'staged', 'superseded', 'retired');
CREATE TYPE load_status AS ENUM ('loading', 'ready', 'failed');

-- validity is the date-of-service range a release covers. It is set only for code systems
-- with date_of_service_versioned (billing code sets) and NULL for everything else; the
-- code_system_version_validity trigger enforces that. Undated versions resolve to the
-- active version in version_for_date.
CREATE TABLE code_system_version
(
    id               UUID                 DEFAULT uuidv7() PRIMARY KEY NOT NULL,
    code_system_id   CITEXT    NOT NULL REFERENCES code_system (id),
    version          TEXT        NOT NULL,
    fhir_version_uri TEXT,
    release_date     date,
    validity         daterange,
    status           code_system_status NOT NULL DEFAULT 'staged',
    load_status      load_status NOT NULL DEFAULT 'loading',
    loaded_at        timestamptz,
    UNIQUE (code_system_id, version),
    UNIQUE (id, code_system_id),
    CHECK (validity IS NULL OR NOT isempty(validity)),
    EXCLUDE USING gist (lower(code_system_id::TEXT) WITH =, validity WITH &&)
        WHERE (status IN ('active', 'superseded') AND validity IS NOT NULL)
);

CREATE UNIQUE INDEX code_system_version_one_active
    ON code_system_version (code_system_id) WHERE status = 'active';

CREATE FUNCTION code_system_version_check_validity()
    RETURNS trigger
    LANGUAGE plpgsql AS $$
DECLARE
    v_dated boolean;
BEGIN
    SELECT date_of_service_versioned INTO v_dated
    FROM code_system
    WHERE id = NEW.code_system_id;

    IF v_dated AND NEW.validity IS NULL THEN
        RAISE EXCEPTION 'code system % is versioned by date of service; validity is required', NEW.code_system_id;
    ELSIF NOT v_dated AND NEW.validity IS NOT NULL THEN
        RAISE EXCEPTION 'code system % is not versioned by date of service; validity must be NULL', NEW.code_system_id;
    END IF;
    RETURN NEW;
END
$$;

CREATE TRIGGER code_system_version_validity
    BEFORE INSERT OR UPDATE OF validity, code_system_id ON code_system_version
    FOR EACH ROW EXECUTE FUNCTION code_system_version_check_validity();

-- code_system_version_one_active cannot be deferred, so the old active version
-- has to be superseded before the new one is activated.
--
-- For a dated version, any other active or superseded version whose range overlaps it is
-- cut back to end where the new range starts; one with nothing left before that point is
-- retired. Part of an old range that runs past the end of the new range is dropped too.
-- Re-activating an older superseded version therefore retires the newer ones that start
-- after it.
CREATE FUNCTION activate_version(p_version_id uuid)
    RETURNS void
    LANGUAGE plpgsql AS $$
DECLARE
    v_code_system_id CITEXT;
    v_status         code_system_status;
    v_load_status    load_status;
    v_validity       daterange;
    v_before         daterange;
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
      AND id <> p_version_id;

    IF v_validity IS NOT NULL THEN
        -- The part of the timeline before the new range starts; empty if it starts at -infinity.
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

-- Lookup by code system id. An untyped literal resolves to the (TEXT, date) URI overload
-- below and returns NULL, so callers passing an id must cast it: 'loinc'::CITEXT.
-- A version with no validity range is not tied to dates of service, so it answers for any
-- date while it is the active version.
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
