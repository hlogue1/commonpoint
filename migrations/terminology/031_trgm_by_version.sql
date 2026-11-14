-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review P2: on an unpartitioned table holding several versions, gin (col gin_trgm_ops) indexes
-- every version together, so a search filtered to one version still walks the others' entries.
-- With btree_gin the index leads with version_id. Partitioned tables don't need this: partition
-- pruning already isolates the version.

CREATE EXTENSION IF NOT EXISTS btree_gin;

DROP INDEX icd_code_long_trgm;
DROP INDEX cpt_code_long_trgm;
DROP INDEX hcpcs_code_long_trgm;
DROP INDEX cdt_code_nomenclature_trgm;
DROP INDEX chv_term_trgm;
DROP INDEX medlineplus_topic_title_trgm;

CREATE INDEX icd_code_long_trgm           ON icd10_code        USING gin (version_id, long_desc gin_trgm_ops);
CREATE INDEX cpt_code_long_trgm           ON cpt_code          USING gin (version_id, long_descriptor gin_trgm_ops);
CREATE INDEX hcpcs_code_long_trgm         ON hcpcs_code        USING gin (version_id, long_desc gin_trgm_ops);
CREATE INDEX cdt_code_nomenclature_trgm   ON cdt_code          USING gin (version_id, nomenclature gin_trgm_ops);
CREATE INDEX chv_term_trgm                ON chv_term          USING gin (version_id, term gin_trgm_ops);
CREATE INDEX medlineplus_topic_title_trgm ON medlineplus_topic USING gin (version_id, title gin_trgm_ops);


---- create above / drop below ----


DROP INDEX icd_code_long_trgm;
DROP INDEX cpt_code_long_trgm;
DROP INDEX hcpcs_code_long_trgm;
DROP INDEX cdt_code_nomenclature_trgm;
DROP INDEX chv_term_trgm;
DROP INDEX medlineplus_topic_title_trgm;

CREATE INDEX icd_code_long_trgm           ON icd10_code        USING gin (long_desc gin_trgm_ops);
CREATE INDEX cpt_code_long_trgm           ON cpt_code          USING gin (long_descriptor gin_trgm_ops);
CREATE INDEX hcpcs_code_long_trgm         ON hcpcs_code        USING gin (long_desc gin_trgm_ops);
CREATE INDEX cdt_code_nomenclature_trgm   ON cdt_code          USING gin (nomenclature gin_trgm_ops);
CREATE INDEX chv_term_trgm                ON chv_term          USING gin (term gin_trgm_ops);
CREATE INDEX medlineplus_topic_title_trgm ON medlineplus_topic USING gin (title gin_trgm_ops);

DROP EXTENSION btree_gin;
