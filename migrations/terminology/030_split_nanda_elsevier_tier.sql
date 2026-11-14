-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C4 (remaining part): NANDA-I and NIC/NOC have different licensors, so one combined tier
-- made per-licensor license tracking impossible. Split 'nanda_elsevier' into 'nanda_i'
-- (NANDA International) and 'elsevier' (NIC, NOC). Enablement rows are untouched: all three
-- systems stay disabled until enabled with a license_reference.

INSERT INTO license_tier_option (id) VALUES ('nanda_i'), ('elsevier');
UPDATE code_system SET license_tier_id = 'nanda_i' WHERE id = 'nanda';
UPDATE code_system SET license_tier_id = 'elsevier' WHERE id IN ('nic', 'noc');
DELETE FROM license_tier_option WHERE id = 'nanda_elsevier';


---- create above / drop below ----


INSERT INTO license_tier_option (id) VALUES ('nanda_elsevier');
UPDATE code_system SET license_tier_id = 'nanda_elsevier' WHERE id IN ('nanda', 'nic', 'noc');
DELETE FROM license_tier_option WHERE id IN ('nanda_i', 'elsevier');
