// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"encoding/json"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

// ---- CDC CVX / MVX (pipe-delimited text from the CDC IIS code set pages) ----

// TODO(verify): column order and encoding of the current CDC downloads. Rows with fewer
// trailing fields are padded.
var (
	cvxCols = []string{"cvx_code", "short_description", "full_vaccine_name", "notes", "status", "internal_id", "nonvaccine", "last_updated"}
	mvxCols = []string{"mvx_code", "manufacturer_name", "notes", "status", "last_updated"}
)

func pipeNoHeader(cols []string) tabular.Layout {
	return tabular.Layout{Kind: tabular.Delimited, Sep: "|", Columns: cols, AllowFewer: true}
}

var CVX = register(&Format{
	Name:         "cdc-cvx",
	Title:        "CDC CVX vaccines administered (pipe-delimited text)",
	Publisher:    "CDC",
	Origin:       Vendor,
	CodeSystems:  []string{"cvx"},
	SourceFormat: "SOURCE_FORMAT_NATIVE",
	Files:        []FileSpec{{ID: "cvx", Pattern: rx(`(web_)?cvx[^/]*\.txt`), Required: true, Layout: pipeNoHeader(cvxCols)}},
	New: func(Options) Checker {
		return &cdcChecker{codeCol: "cvx_code", code: regexp.MustCompile(`^[0-9]{1,3}$`)}
	},
})

var MVX = register(&Format{
	Name:         "cdc-mvx",
	Title:        "CDC MVX vaccine manufacturers (pipe-delimited text)",
	Publisher:    "CDC",
	Origin:       Vendor,
	CodeSystems:  []string{"mvx"},
	SourceFormat: "SOURCE_FORMAT_NATIVE",
	Files:        []FileSpec{{ID: "mvx", Pattern: rx(`(web_)?mvx[^/]*\.txt`), Required: true, Layout: pipeNoHeader(mvxCols)}},
	New: func(Options) Checker {
		return &cdcChecker{codeCol: "mvx_code", code: regexp.MustCompile(`^[A-Z]{2,3}$`)}
	},
})

type cdcChecker struct {
	codeCol string
	code    *regexp.Regexp
	seen    map[string]struct{}
	latest  time.Time
}

func (k *cdcChecker) Row(c *Ctx, rec tabular.Record) {
	if k.seen == nil {
		k.seen = map[string]struct{}{}
	}
	code := strings.TrimSpace(rec.Get(k.codeCol))
	if !k.code.MatchString(code) {
		c.Errorf(rec.Line, "bad_code", "%s %q has an unexpected form", k.codeCol, code)
	}
	if _, dup := k.seen[code]; dup {
		c.Errorf(rec.Line, "duplicate_code", "%s appears more than once", code)
	}
	k.seen[code] = struct{}{}
	if d := strings.TrimSpace(rec.Get("last_updated")); d != "" {
		t, err := time.Parse("1/2/2006", d)
		if err != nil {
			c.Warnf(rec.Line, "bad_date", "last_updated %q is not M/D/YYYY", d)
		} else if t.After(k.latest) {
			k.latest = t
		}
	}
}

func (k *cdcChecker) Finish(c *Ctx) {
	c.Meta.AddCount("codes", int64(len(k.seen)))
	if !k.latest.IsZero() {
		// CDC publishes no version; the newest change date stands in for it.
		c.Meta.Version = k.latest.Format("20060102")
		c.Meta.ReleaseDate = isoDate(k.latest)
		c.Meta.Notes = append(c.Meta.Notes, "version is the newest last_updated date")
	}
}

// ---- NUCC Health Care Provider Taxonomy (CSV) ----

var nuccName = regexp.MustCompile(`(?i)nucc_taxonomy_(\d{2,3})\.csv`)

var NUCC = register(&Format{
	Name:         "nucc-csv",
	Title:        "NUCC Health Care Provider Taxonomy (CSV)",
	Publisher:    "NUCC",
	Origin:       Vendor,
	CodeSystems:  []string{"nucc"},
	SourceFormat: "SOURCE_FORMAT_NATIVE",
	Files: []FileSpec{{ID: "taxonomy", Pattern: rx(`nucc_taxonomy_\d+\.csv`), Required: true,
		Layout: csvLayout("Code", "Grouping", "Classification")}},
	Sniff: func(sel *Selection, md *Metadata, _ Options) {
		if f := sel.First("taxonomy"); f != nil {
			if m := nuccName.FindStringSubmatch(f.Name); m != nil {
				v := m[1] // "251" is release 25.1
				md.Version = v[:len(v)-1] + "." + v[len(v)-1:]
			}
		}
	},
	New: func(Options) Checker { return &cdcChecker{codeCol: "Code", code: regexp.MustCompile(`^[0-9A-Z]{9}X$`)} },
})

// ---- MedDRA ASCII ($-delimited) ----

func dollar(cols ...string) tabular.Layout {
	return tabular.Layout{Kind: tabular.Delimited, Sep: "$", Columns: cols}
}

var MedDRA = register(&Format{
	Name:         "meddra-ascii",
	Title:        "MedDRA ASCII distribution (MedAscii/*.asc)",
	Publisher:    "MedDRA MSSO",
	Origin:       Vendor,
	CodeSystems:  []string{"meddra"},
	SourceFormat: "SOURCE_FORMAT_NATIVE",
	// Spec order matters: each level is read before the level that references it.
	Files: []FileSpec{
		// TODO(verify): meddra_release.asc fields after version and language.
		{ID: "release", Pattern: rx(`meddra_release\.asc`), Layout: tabular.Layout{Kind: tabular.Delimited, Sep: "$", Columns: []string{"version", "language"}, AllowFewer: true}},
		{ID: "soc", Pattern: rx(`soc\.asc`), Required: true, Layout: dollar("soc_code", "soc_name", "soc_abbrev", "soc_whoart_code", "soc_harts_code", "soc_costart_sym", "soc_icd9_code", "soc_icd9cm_code", "soc_icd10_code", "soc_jart_code")},
		{ID: "hlgt", Pattern: rx(`hlgt\.asc`), Required: true, Layout: dollar("hlgt_code", "hlgt_name", "hlgt_whoart_code", "hlgt_harts_code", "hlgt_costart_sym", "hlgt_icd9_code", "hlgt_icd9cm_code", "hlgt_icd10_code", "hlgt_jart_code")},
		{ID: "hlt", Pattern: rx(`hlt\.asc`), Required: true, Layout: dollar("hlt_code", "hlt_name", "hlt_whoart_code", "hlt_harts_code", "hlt_costart_sym", "hlt_icd9_code", "hlt_icd9cm_code", "hlt_icd10_code", "hlt_jart_code")},
		{ID: "pt", Pattern: rx(`pt\.asc`), Required: true, Layout: dollar("pt_code", "pt_name", "null_field", "pt_soc_code", "pt_whoart_code", "pt_harts_code", "pt_costart_sym", "pt_icd9_code", "pt_icd9cm_code", "pt_icd10_code", "pt_jart_code")},
		{ID: "llt", Pattern: rx(`llt\.asc`), Required: true, Layout: dollar("llt_code", "llt_name", "pt_code", "llt_whoart_code", "llt_harts_code", "llt_costart_sym", "llt_icd9_code", "llt_icd9cm_code", "llt_icd10_code", "llt_currency", "llt_jart_code")},
		{ID: "soc_hlgt", Pattern: rx(`soc_hlgt\.asc`), Layout: dollar("soc_code", "hlgt_code")},
		{ID: "hlgt_hlt", Pattern: rx(`hlgt_hlt\.asc`), Layout: dollar("hlgt_code", "hlt_code")},
		{ID: "hlt_pt", Pattern: rx(`hlt_pt\.asc`), Layout: dollar("hlt_code", "pt_code")},
		{ID: "mdhier", Pattern: rx(`mdhier\.asc`), Required: true, Layout: dollar("pt_code", "hlt_code", "hlgt_code", "soc_code", "pt_name", "hlt_name", "hlgt_name", "soc_name", "soc_abbrev", "null_field", "pt_soc_code", "primary_soc_fg")},
		{ID: "intl_ord", Pattern: rx(`intl_ord\.asc`), Layout: dollar("intl_ord_code", "soc_code")},
	},
	New: func(Options) Checker { return &meddraChecker{sets: map[string]map[string]struct{}{}} },
})

type meddraChecker struct {
	sets       map[string]map[string]struct{} // level -> codes
	currentLLT int64
}

func (m *meddraChecker) add(level, code string) {
	if m.sets[level] == nil {
		m.sets[level] = map[string]struct{}{}
	}
	m.sets[level][code] = struct{}{}
}

func (m *meddraChecker) ref(c *Ctx, rec tabular.Record, col, level string) {
	v := rec.Get(col)
	if len(v) != 8 || !isDigits(v) {
		c.Errorf(rec.Line, "bad_code", "%s %q is not an 8-digit MedDRA code", col, v)
		return
	}
	if _, ok := m.sets[level][v]; !ok {
		c.Errorf(rec.Line, "unknown_code", "%s %s is not in %s.asc", col, v, level)
	}
}

func (m *meddraChecker) Row(c *Ctx, rec tabular.Record) {
	switch id := c.Spec.ID; id {
	case "release":
		if v := rec.Get("version"); v != "" {
			c.Meta.Version = v
		}
	case "soc", "hlgt", "hlt", "pt", "llt":
		code := rec.Get(id + "_code")
		if len(code) != 8 || !isDigits(code) {
			c.Errorf(rec.Line, "bad_code", "%s_code %q is not an 8-digit MedDRA code", id, code)
		}
		if rec.Get(id+"_name") == "" {
			c.Errorf(rec.Line, "empty_name", "%s %s has no name", id, code)
		}
		m.add(id, code)
		if id == "pt" {
			m.ref(c, rec, "pt_soc_code", "soc")
		}
		if id == "llt" {
			m.ref(c, rec, "pt_code", "pt")
			switch rec.Get("llt_currency") {
			case "Y":
				m.currentLLT++
			case "N":
			default:
				c.Errorf(rec.Line, "bad_currency", "llt_currency %q is not Y or N", rec.Get("llt_currency"))
			}
		}
	case "soc_hlgt":
		m.ref(c, rec, "soc_code", "soc")
		m.ref(c, rec, "hlgt_code", "hlgt")
	case "hlgt_hlt":
		m.ref(c, rec, "hlgt_code", "hlgt")
		m.ref(c, rec, "hlt_code", "hlt")
	case "hlt_pt":
		m.ref(c, rec, "hlt_code", "hlt")
		m.ref(c, rec, "pt_code", "pt")
	case "mdhier":
		m.ref(c, rec, "pt_code", "pt")
		m.ref(c, rec, "hlt_code", "hlt")
		m.ref(c, rec, "hlgt_code", "hlgt")
		m.ref(c, rec, "soc_code", "soc")
		if f := rec.Get("primary_soc_fg"); f != "Y" && f != "N" {
			c.Errorf(rec.Line, "bad_flag", "primary_soc_fg %q is not Y or N", f)
		}
	}
}

func (m *meddraChecker) Finish(c *Ctx) {
	for _, l := range []string{"soc", "hlgt", "hlt", "pt", "llt"} {
		c.Meta.AddCount(strings.ToUpper(l)+" codes", int64(len(m.sets[l])))
	}
	c.Meta.AddCount("current LLTs", m.currentLLT)
}

// ---- FHIR CodeSystem (JSON) ----

// FHIRCodeSystem ingests a FHIR R4 CodeSystem resource. It's the generic route for vendors that
// publish FHIR rather than a native format. The code system comes from the resource url.
var FHIRCodeSystem = register(&Format{
	Name:         "fhir-codesystem",
	Title:        "FHIR R4 CodeSystem resource (JSON, content = complete)",
	Publisher:    "any",
	Origin:       Vendor,
	SourceFormat: "SOURCE_FORMAT_FHIR_CODESYSTEM_JSON",
	NoDetect:     true,
	Files:        []FileSpec{{ID: "codesystem", Pattern: rx(`[^/]+\.json`), Required: true}},
	New:          func(Options) Checker { return &fhirChecker{} },
})

type fhirConcept struct {
	Code       string        `json:"code"`
	Display    string        `json:"display"`
	Definition string        `json:"definition"`
	Concept    []fhirConcept `json:"concept"`
}

type fhirCS struct {
	ResourceType string        `json:"resourceType"`
	URL          string        `json:"url"`
	Version      string        `json:"version"`
	Status       string        `json:"status"`
	Date         string        `json:"date"`
	Content      string        `json:"content"`
	Count        *int64        `json:"count"`
	Concept      []fhirConcept `json:"concept"`
}

type fhirChecker struct{}

func (fhirChecker) Row(*Ctx, tabular.Record) {}
func (fhirChecker) Finish(*Ctx)              {}

func (fhirChecker) Stream(c *Ctx, r io.Reader) error {
	var cs fhirCS
	dec := json.NewDecoder(r)
	if err := dec.Decode(&cs); err != nil {
		return fmt.Errorf("JSON: %w", err)
	}
	if cs.ResourceType != "CodeSystem" {
		return fmt.Errorf("resourceType is %q; expected CodeSystem", cs.ResourceType)
	}
	if cs.URL == "" {
		c.Errorf(0, "missing_url", "CodeSystem.url is required")
	}
	c.Meta.CodeSystemURI = cs.URL
	if known := CodeSystemForURI(cs.URL); known != nil {
		c.Meta.CodeSystemID = known.ID
	}
	c.Meta.Version = cs.Version
	if len(cs.Date) >= 10 {
		c.Meta.ReleaseDate = cs.Date[:10]
	}
	if cs.Content != "complete" {
		c.Errorf(0, "not_complete", "CodeSystem.content is %q; only complete code systems can be installed", cs.Content)
	}
	seen := map[string]struct{}{}
	var walk func([]fhirConcept, int)
	walk = func(cc []fhirConcept, depth int) {
		for _, k := range cc {
			if k.Code == "" {
				c.Errorf(0, "empty_code", "a concept has no code")
			} else if _, dup := seen[k.Code]; dup {
				c.Errorf(0, "duplicate_code", "code %q appears more than once", k.Code)
			}
			seen[k.Code] = struct{}{}
			if k.Display == "" {
				c.Warnf(0, "empty_display", "code %q has no display", k.Code)
			}
			walk(k.Concept, depth+1)
		}
	}
	walk(cs.Concept, 0)
	AddRows(r, int64(len(seen)))
	c.Meta.AddCount("concepts", int64(len(seen)))
	if cs.Count != nil && *cs.Count != int64(len(seen)) {
		c.Errorf(0, "count_mismatch", "CodeSystem.count is %s but %d concepts are present", strconv.FormatInt(*cs.Count, 10), len(seen))
	}
	return nil
}
