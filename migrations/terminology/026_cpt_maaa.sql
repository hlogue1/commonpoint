-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C8: the CPT code CHECK accepts the M suffix (Administrative MAAA codes), but
-- cpt_code_type had no value for them. Add 'MAAA', and tie each category to its code shape so the
-- loader can't mislabel one:
--   I     five digits         II   ####F        III  ####T
--   PLA   ####U               MAAA ####M
-- MAAA tests that have a numeric (Category I) code stay category I.
-- The CHECK compares category::text: a value added by ALTER TYPE can't be used as an enum literal
-- in the same transaction.

ALTER TYPE cpt_code_type ADD VALUE 'MAAA';

ALTER TABLE cpt_code ADD CONSTRAINT cpt_code_category_matches_code CHECK (
    CASE category::text
        WHEN 'I'    THEN code ~ '^[0-9]{5}$'
        WHEN 'II'   THEN code ~ 'F$'
        WHEN 'III'  THEN code ~ 'T$'
        WHEN 'PLA'  THEN code ~ 'U$'
        WHEN 'MAAA' THEN code ~ 'M$'
    END);


---- create above / drop below ----


ALTER TABLE cpt_code DROP CONSTRAINT cpt_code_category_matches_code;
ALTER TYPE cpt_code_type RENAME TO cpt_code_type_with_maaa;
CREATE TYPE cpt_code_type AS ENUM ('I', 'II', 'III', 'PLA');
ALTER TABLE cpt_code ALTER COLUMN category TYPE cpt_code_type USING category::text::cpt_code_type;
DROP TYPE cpt_code_type_with_maaa;
