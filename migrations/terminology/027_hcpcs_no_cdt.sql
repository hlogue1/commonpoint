-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- Review C9: the CMS HCPCS Level II file carries the D-codes, which are ADA CDT content. CDT is
-- licensed separately (tier 'ada'), so it may only arrive through the cdt code system. The HCPCS
-- loader skips D rows; this CHECK makes sure none get through the open HCPCS tier.

ALTER TABLE hcpcs_code ADD CONSTRAINT hcpcs_code_not_cdt CHECK (code !~ '^D');


---- create above / drop below ----


ALTER TABLE hcpcs_code DROP CONSTRAINT hcpcs_code_not_cdt;
