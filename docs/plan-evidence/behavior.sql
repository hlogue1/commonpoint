\set ON_ERROR_STOP 0
\pset footer off
-- helper: load one SNOMED version via the documented partition recipe
CREATE OR REPLACE FUNCTION t_load_snomed(p_ver text) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; s text;
BEGIN
  INSERT INTO code_system_version(code_system_id, version) VALUES ('snomed', p_ver) RETURNING id INTO v;
  INSERT INTO snomed_release(version_id) VALUES (v);
  s := replace(v::text,'-','');
  EXECUTE format('CREATE TABLE snomed_concept_%s (LIKE snomed_concept INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED)', s);
  EXECUTE format('ALTER TABLE snomed_concept_%s ADD CHECK (version_id = %L)', s, v);
  EXECUTE format('INSERT INTO snomed_concept_%s VALUES (%L,138875005,true,900000000000207008,false,''SNOMED CT Concept (SNOMED RT+CTV3)'',''SNOMED CT Concept'',''SNOMED RT+CTV3''),(%L,900000000000207008,true,900000000000207008,false,''Core module (core metadata concept)'',''Core module'',''core metadata concept'')', s, v, v);
  EXECUTE format('ALTER TABLE snomed_concept_%s ADD PRIMARY KEY (version_id, id)', s);
  EXECUTE format('ALTER TABLE snomed_concept_%1$s ADD CONSTRAINT snomed_concept_%1$s_module_fk FOREIGN KEY (version_id, module_id) REFERENCES snomed_concept_%1$s (version_id, id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED', s);
  EXECUTE format('ALTER TABLE snomed_concept ATTACH PARTITION snomed_concept_%s FOR VALUES IN (%L)', s, v);
  EXECUTE format('CREATE TABLE snomed_description_%s (LIKE snomed_description INCLUDING DEFAULTS INCLUDING CONSTRAINTS INCLUDING GENERATED)', s);
  EXECUTE format('ALTER TABLE snomed_description_%s ADD CHECK (version_id = %L)', s, v);
  EXECUTE format('INSERT INTO snomed_description_%s VALUES (%L,517038018,138875005,true,900000000000207008,''en'',''synonym'',''SNOMED CT Concept'',900000000000448009)', s, v);
  EXECUTE format('ALTER TABLE snomed_description_%s ADD PRIMARY KEY (version_id, id)', s);
  EXECUTE format('ALTER TABLE snomed_description ATTACH PARTITION snomed_description_%s FOR VALUES IN (%L)', s, v);
  EXECUTE format('CREATE TABLE snomed_language_member_%s (LIKE snomed_language_member INCLUDING DEFAULTS INCLUDING CONSTRAINTS)', s);
  EXECUTE format('ALTER TABLE snomed_language_member_%s ADD CHECK (version_id = %L)', s, v);
  EXECUTE format('INSERT INTO snomed_language_member_%s VALUES (%L,900000000000509007,517038018,''preferred'')', s, v);
  EXECUTE format('ALTER TABLE snomed_language_member_%s ADD PRIMARY KEY (version_id, refset_id, description_id)', s);
  EXECUTE format('ALTER TABLE snomed_language_member ATTACH PARTITION snomed_language_member_%s FOR VALUES IN (%L)', s, v);
  UPDATE code_system_version SET load_status='ready', loaded_at=now() WHERE id=v;
  RETURN v;
END $$;

\echo '== T1 activate a version that is still loading (expect ERROR)'
INSERT INTO code_system_version(code_system_id, version) VALUES ('snomed','loading-one');
SELECT activate_version((SELECT id FROM code_system_version WHERE version='loading-one'));
DELETE FROM code_system_version WHERE version='loading-one';

\echo '== T2 load two SNOMED versions via partition recipe, activate both in turn'
SELECT t_load_snomed('20260301') AS v1 \gset
SELECT t_load_snomed('20260901') AS v2 \gset
SELECT activate_version(:'v1');
SELECT activate_version(:'v2');
SELECT version, status, load_status FROM code_system_version WHERE code_system_id='snomed' ORDER BY version;
SELECT version_for_date('snomed'::citext, '2020-01-01') = :'v2' AS undated_resolves_to_active;

\echo '== T3 rollback = activate_version(previous)'
SELECT activate_version(:'v1');
SELECT version, status FROM code_system_version WHERE code_system_id='snomed' ORDER BY version;

\echo '== T4 retire v2 by DETACH + DROP in reverse order'
DO $$ DECLARE s text := replace((SELECT id FROM code_system_version WHERE version='20260901')::text,'-','');
BEGIN
  EXECUTE format('ALTER TABLE snomed_language_member DETACH PARTITION snomed_language_member_%s', s);
  EXECUTE format('ALTER TABLE snomed_description DETACH PARTITION snomed_description_%s', s);
  EXECUTE format('ALTER TABLE snomed_concept DETACH PARTITION snomed_concept_%s', s);
  EXECUTE format('DROP TABLE snomed_language_member_%1$s, snomed_description_%1$s, snomed_concept_%1$s', s);
END $$;
DELETE FROM code_system_version WHERE id = :'v2';
SELECT count(*) AS snomed_partitions_left FROM pg_inherits i JOIN pg_class c ON c.oid=i.inhparent WHERE c.relname LIKE 'snomed_%';

\echo '== T5 validity trigger (expect 2 ERRORs)'
INSERT INTO code_system_version(code_system_id, version) VALUES ('icd10cm','no-validity');
INSERT INTO code_system_version(code_system_id, version, validity) VALUES ('snomed','has-validity','[2026-01-01,)');

\echo '== T6 ICD-10-CM date of service: FY2026, FY2027, then April 2027 update'
INSERT INTO code_system_version(code_system_id, version, validity, load_status) VALUES
 ('icd10cm','2026','[2025-10-01,2026-10-01)','ready'),
 ('icd10cm','2027','[2026-10-01,2027-10-01)','ready'),
 ('icd10cm','2027-04','[2027-04-01,2027-10-01)','ready');
SELECT activate_version(id) FROM code_system_version WHERE code_system_id='icd10cm' AND version='2026';
SELECT activate_version(id) FROM code_system_version WHERE code_system_id='icd10cm' AND version='2027';
SELECT activate_version(id) FROM code_system_version WHERE code_system_id='icd10cm' AND version='2027-04';
SELECT version, status, validity FROM code_system_version WHERE code_system_id='icd10cm' ORDER BY version;
SELECT d, (SELECT version FROM code_system_version WHERE id = version_for_date('icd10cm'::citext, d)) AS resolves_to
FROM unnest(array['2026-09-15','2026-10-15','2027-05-01']::date[]) d;

\echo '== T7 roll back the April update by re-activating 2027'
SELECT activate_version(id) FROM code_system_version WHERE code_system_id='icd10cm' AND version='2027';
SELECT version, status, validity FROM code_system_version WHERE code_system_id='icd10cm' ORDER BY version;
SELECT (SELECT version FROM code_system_version WHERE id = version_for_date('icd10cm'::citext, '2027-05-01')) AS may_2027_resolves_to;

\echo '== T8 untyped literal picks the URI overload'
SELECT version_for_date('icd10cm', '2026-10-15') AS untyped_literal_result;

\echo '== T9 lookup through concept_index needs an enablement row'
SELECT count(*) AS rows_without_enablement FROM lookup('snomed','138875005');
INSERT INTO code_system_enablement VALUES ('snomed', true, 'UMLS test');
SELECT * FROM lookup('snomed','138875005');
