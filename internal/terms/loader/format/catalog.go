// SPDX-License-Identifier: GPL-3.0-or-later

package format

import "strings"

// CodeSystem mirrors a row of the code_system seed in migrations/terminology/001_core.sql,
// so ingest can check a request before it reaches the server. catalog_test.go keeps the two
// in sync. The database stays authoritative (validity trigger, enablement, license tier).
type CodeSystem struct {
	ID  string
	URI string
	// DateOfService: versions carry a validity range (billing code sets).
	DateOfService bool
	// SABs are the UMLS source abbreviations whose content belongs to this code system.
	SABs []string
}

// Catalog lists every code system in the seed.
//
// TODO(verify): UMLS SABs marked below against the current MRSAB before relying on them.
var Catalog = []CodeSystem{
	{ID: "snomed", URI: "http://snomed.info/sct", SABs: []string{"SNOMEDCT_US"}},
	{ID: "loinc", URI: "http://loinc.org", SABs: []string{"LNC"}},
	{ID: "rxnorm", URI: "http://www.nlm.nih.gov/research/umls/rxnorm", SABs: []string{"RXNORM"}},
	{ID: "medrt", URI: "http://va.gov/terminology/medrt", SABs: []string{"MED-RT"}},
	{ID: "atc", URI: "http://www.whocc.no/atc", SABs: []string{"ATC"}},
	{ID: "cms_frf", URI: "urn:commonpoint:cs:cms_frf"},
	{ID: "uspmg", URI: "urn:commonpoint:cs:uspmg", SABs: []string{"USPMG"}},
	{ID: "icd10cm", URI: "http://hl7.org/fhir/sid/icd-10-cm", DateOfService: true, SABs: []string{"ICD10CM"}},
	{ID: "icd10pcs", URI: "http://www.cms.gov/Medicare/Coding/ICD10", DateOfService: true, SABs: []string{"ICD10PCS"}},
	{ID: "cpt", URI: "http://www.ama-assn.org/go/cpt", DateOfService: true, SABs: []string{"CPT"}},
	{ID: "hcpcs", URI: "http://www.cms.gov/Medicare/Coding/HCPCSReleaseCodeSets", DateOfService: true, SABs: []string{"HCPCS"}},
	{ID: "cdt", URI: "http://www.ada.org/cdt", DateOfService: true, SABs: []string{"CDT"}},
	{ID: "icd9cm", URI: "http://hl7.org/fhir/sid/icd-9-cm", SABs: []string{"ICD9CM"}},
	{ID: "abc", URI: "urn:commonpoint:cs:abc"},
	{ID: "sop", URI: "https://nahdo.org/sopt", SABs: []string{"SOP"}},
	{ID: "ncci", URI: "urn:commonpoint:cs:ncci", DateOfService: true},
	{ID: "cvx", URI: "http://hl7.org/fhir/sid/cvx", SABs: []string{"CVX"}},
	{ID: "mvx", URI: "http://terminology.hl7.org/CodeSystem/MVX", SABs: []string{"MVX"}},
	{ID: "nucc", URI: "http://nucc.org/provider-taxonomy", SABs: []string{"NUCCHCPT"}}, // TODO(verify)
	{ID: "cdc_race_ethnicity", URI: "urn:oid:2.16.840.1.113883.6.238", SABs: []string{"CDCREC"}},
	{ID: "ucum", URI: "http://unitsofmeasure.org"},
	{ID: "ccsr_dx", URI: "urn:commonpoint:cs:ccsr_dx"},
	{ID: "ccsr_pr", URI: "urn:commonpoint:cs:ccsr_pr"},
	{ID: "ccs", URI: "urn:commonpoint:cs:ccs"},
	{ID: "ccs_ml", URI: "urn:commonpoint:cs:ccs_ml"},
	{ID: "nanda", URI: "urn:commonpoint:cs:nanda", SABs: []string{"NANDA-I"}},
	{ID: "nic", URI: "urn:commonpoint:cs:nic", SABs: []string{"NIC"}},
	{ID: "noc", URI: "urn:commonpoint:cs:noc", SABs: []string{"NOC"}},
	{ID: "omaha", URI: "urn:commonpoint:cs:omaha", SABs: []string{"OMS"}},
	{ID: "pnds", URI: "urn:commonpoint:cs:pnds", SABs: []string{"PNDS"}},
	{ID: "icpc2", URI: "http://hl7.org/fhir/sid/icpc-2", SABs: []string{"ICPC2EENG"}},           // TODO(verify)
	{ID: "icpc2plus", URI: "urn:commonpoint:cs:icpc2plus", SABs: []string{"ICPC2P"}},            // TODO(verify)
	{ID: "icpc2_icd10", URI: "urn:commonpoint:cs:icpc2_icd10", SABs: []string{"ICPC2ICD10ENG"}}, // TODO(verify)
	{ID: "icf", URI: "urn:commonpoint:cs:icf", SABs: []string{"ICF"}},
	{ID: "hgnc", URI: "http://www.genenames.org", SABs: []string{"HGNC"}},
	{ID: "hpo", URI: "http://human-phenotype-ontology.org", SABs: []string{"HPO"}},
	{ID: "mondo", URI: "urn:commonpoint:cs:mondo"},
	{ID: "orphanet", URI: "urn:commonpoint:cs:orphanet", SABs: []string{"ORPHANET"}},
	{ID: "ncit", URI: "http://ncicb.nci.nih.gov/xml/owl/EVS/Thesaurus.owl", SABs: []string{"NCI"}},
	{ID: "pdq", URI: "urn:commonpoint:cs:pdq", SABs: []string{"PDQ"}},
	{ID: "meddra", URI: "http://terminology.hl7.org/CodeSystem/mdr", SABs: []string{"MDR"}},
	{ID: "umdns", URI: "urn:commonpoint:cs:umdns", SABs: []string{"UMD"}}, // TODO(verify)
	{ID: "chv", URI: "urn:commonpoint:cs:chv", SABs: []string{"CHV"}},
	{ID: "medlineplus", URI: "urn:commonpoint:cs:medlineplus", SABs: []string{"MEDLINEPLUS"}},
	// The whole Metathesaurus: ingest with no SAB filter.
	{ID: "umls", URI: "urn:commonpoint:cs:umls"},
}

// LookupCodeSystem returns the catalog entry for id, or nil.
func LookupCodeSystem(id string) *CodeSystem {
	for i := range Catalog {
		if strings.EqualFold(Catalog[i].ID, id) {
			return &Catalog[i]
		}
	}
	return nil
}

// CodeSystemForURI returns the catalog entry with the canonical URI, or nil.
func CodeSystemForURI(uri string) *CodeSystem {
	for i := range Catalog {
		if Catalog[i].URI == uri {
			return &Catalog[i]
		}
	}
	return nil
}

// CodeSystemForSAB returns the code system a UMLS SAB belongs to, or nil.
func CodeSystemForSAB(sab string) *CodeSystem {
	for i := range Catalog {
		for _, s := range Catalog[i].SABs {
			if strings.EqualFold(s, sab) {
				return &Catalog[i]
			}
		}
	}
	return nil
}

// NativeFormats returns the vendor formats that produce a code system.
func NativeFormats(codeSystemID string) []*Format {
	var out []*Format
	for _, f := range All() {
		for _, cs := range f.CodeSystems {
			if strings.EqualFold(cs, codeSystemID) {
				out = append(out, f)
			}
		}
	}
	return out
}
