// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"bufio"
	"encoding/xml"
	"fmt"
	"io"
	"regexp"
	"strconv"
	"strings"

	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

// CMS "order" files (ICD-10-CM and ICD-10-PCS code descriptions in tabular order) share one
// fixed-width layout: order number (1-5), code (7-13), header flag (15: 0 = category/header,
// 1 = valid for submission), short description (17-76), long description (78-end).
var cmsOrderLayout = tabular.Layout{Kind: tabular.Fixed, MinLen: 17, Fields: []tabular.FixedField{
	{Name: "order", Start: 1, End: 5},
	{Name: "code", Start: 7, End: 13},
	{Name: "valid", Start: 15, End: 15},
	{Name: "short", Start: 17, End: 76},
	{Name: "long", Start: 78},
}}

// Release names: icd10cm_order_2027.txt, icd10cm-order-April-2025.txt, icd10pcs_order_2027.txt.
// Addenda files (icd10cm_order_addenda_2027.txt) are not code files and must not match.
var icdReleaseName = regexp.MustCompile(`(?i)icd10(?:cm|pcs)[-_](?:order|tabular|tables)[-_](?:(april)[-_])?(\d{4})`)

func sniffICD(sel *Selection, md *Metadata, _ Options) {
	m := firstSubmatch(sel, icdReleaseName)
	if m == nil {
		return
	}
	y, _ := strconv.Atoi(m[2])
	md.Version = m[2]
	md.ValiditySuggestion = fiscalYearValidity(y)
	if strings.EqualFold(m[1], "april") {
		md.Version = m[2] + "-04"
		md.ValiditySuggestion = fmt.Sprintf("[%d-04-01,%d-10-01)", y, y)
	}
}

type orderChecker struct {
	system     string // "cm" or "pcs"
	lastOrder  int
	valid      int64
	headers    int64
	xmlLeaves  int64
	xmlCodes   int64
	xmlVersion string
}

var (
	icd10cmCode  = regexp.MustCompile(`^[A-Z][0-9][0-9A-Z]{1,5}$`)
	icd10cmDiag  = regexp.MustCompile(`^[A-Z][0-9][0-9A-Z](\.[0-9A-Z]{1,4})?$`)
	icd10pcsCode = regexp.MustCompile(`^[0-9A-HJ-NP-Z]{1,7}$`) // PCS never uses I or O
)

func (o *orderChecker) Row(c *Ctx, rec tabular.Record) {
	n, ok := atoi(rec.Get("order"))
	if !ok {
		c.Errorf(rec.Line, "bad_order", "order number %q is not numeric", rec.Get("order"))
	} else {
		if n <= o.lastOrder {
			c.Errorf(rec.Line, "order_not_increasing", "order number %d follows %d", n, o.lastOrder)
		}
		o.lastOrder = n
	}
	code := rec.Get("code")
	switch rec.Get("valid") {
	case "1":
		o.valid++
	case "0":
		o.headers++
	default:
		c.Errorf(rec.Line, "bad_flag", "header flag %q is not 0 or 1", rec.Get("valid"))
	}
	switch o.system {
	case "cm":
		if !icd10cmCode.MatchString(code) {
			c.Errorf(rec.Line, "bad_code", "%q is not an ICD-10-CM code (no dot, 3-7 characters)", code)
		}
	case "pcs":
		if !icd10pcsCode.MatchString(code) || (rec.Get("valid") == "1" && len(code) != 7) {
			c.Errorf(rec.Line, "bad_code", "%q is not an ICD-10-PCS code (7 characters when valid, no I or O)", code)
		}
	}
	if rec.Get("long") == "" {
		c.Errorf(rec.Line, "empty_description", "code %s has no long description", code)
	}
}

// Stream reads the ICD-10-CM tabular XML: counts <diag> codes and leaves (codes with no
// child diag, i.e. valid for submission) and reads <version>.
func (o *orderChecker) Stream(c *Ctx, r io.Reader) error {
	dec := xml.NewDecoder(bufio.NewReaderSize(r, 1<<20))
	type frame struct {
		name     string
		children int
		code     string
	}
	var stack []frame
	var text strings.Builder
	var root string
	for {
		tok, err := dec.Token()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("XML: %w", err)
		}
		switch t := tok.(type) {
		case xml.StartElement:
			n := t.Name.Local
			if root == "" {
				root = n
				if c.Spec.ID == "tabular" && !strings.EqualFold(root, "ICD10CM.tabular") {
					return fmt.Errorf("root element is <%s>; expected <ICD10CM.tabular>", root)
				}
			}
			if n == "diag" && len(stack) > 0 {
				for i := len(stack) - 1; i >= 0; i-- {
					if stack[i].name == "diag" {
						stack[i].children++
						break
					}
				}
			}
			stack = append(stack, frame{name: n})
			text.Reset()
		case xml.CharData:
			text.Write(t)
		case xml.EndElement:
			if len(stack) == 0 {
				return fmt.Errorf("unbalanced </%s>", t.Name.Local)
			}
			top := stack[len(stack)-1]
			stack = stack[:len(stack)-1]
			v := strings.TrimSpace(text.String())
			switch {
			case top.name == "version" && len(stack) == 1:
				o.xmlVersion = v
			case top.name == "name" && len(stack) > 0 && stack[len(stack)-1].name == "diag":
				stack[len(stack)-1].code = v
				if !icd10cmDiag.MatchString(v) {
					line, _ := dec.InputPos()
					c.Errorf(int64(line), "bad_code", "diag name %q is not an ICD-10-CM code", v)
				}
			case top.name == "diag":
				o.xmlCodes++
				if top.children == 0 {
					o.xmlLeaves++
				}
				AddRows(r, 1)
			}
			text.Reset()
		}
	}
	return nil
}

func (o *orderChecker) Finish(c *Ctx) {
	if o.valid+o.headers > 0 {
		c.Meta.AddCount("codes valid for submission", o.valid)
		c.Meta.AddCount("header codes", o.headers)
	}
	if o.xmlCodes > 0 {
		c.Meta.AddCount("tabular diag codes", o.xmlCodes)
		c.Meta.AddCount("tabular leaf codes", o.xmlLeaves)
	}
	if o.xmlVersion != "" && c.Meta.Version == "" {
		c.Meta.Version = o.xmlVersion
	}
	if o.valid > 0 && o.xmlLeaves > 0 && o.valid != o.xmlLeaves {
		c.Warnf(0, "count_mismatch", "order file has %d valid codes but the tabular XML has %d leaf codes; are they from the same release?", o.valid, o.xmlLeaves)
	}
}

var ICD10CM = register(&Format{
	Name:         "icd10cm",
	Title:        "ICD-10-CM code descriptions (order file) and/or tabular XML",
	Publisher:    "CDC NCHS / CMS",
	Origin:       Vendor,
	CodeSystems:  []string{"icd10cm"},
	SourceFormat: "SOURCE_FORMAT_ICD10CM_XML",
	Files: []FileSpec{
		{ID: "order", Pattern: rx(`icd10cm[-_]order[-_](?:april[-_])?\d{4}\.txt`), OneOf: "codes", Layout: cmsOrderLayout},
		{ID: "tabular", Pattern: rx(`icd10cm[-_]tabular[-_](?:april[-_])?\d{4}\.xml`), OneOf: "codes"},
	},
	Sniff: sniffICD,
	New:   func(Options) Checker { return &orderChecker{system: "cm"} },
})

var ICD10PCS = register(&Format{
	Name:         "icd10pcs",
	Title:        "ICD-10-PCS order file (+ optional tables XML)",
	Publisher:    "CMS",
	Origin:       Vendor,
	CodeSystems:  []string{"icd10pcs"},
	SourceFormat: "SOURCE_FORMAT_ICD10PCS",
	Files: []FileSpec{
		{ID: "order", Pattern: rx(`icd10pcs[-_]order[-_](?:april[-_])?\d{4}\.txt`), Required: true, Layout: cmsOrderLayout},
		// TODO(verify): element names of the PCS tables XML; only well-formedness is checked.
		{ID: "tables", Pattern: rx(`icd10pcs[-_]tables[-_](?:april[-_])?\d{4}\.xml`)},
	},
	Sniff: sniffICD,
	New:   func(Options) Checker { return &orderChecker{system: "pcs"} },
})

// ---- HCPCS Level II (CMS alpha-numeric file) ----

// TODO(verify): offsets past the short description against the current CMS record layout;
// ingest reads only the leading fields.
var hcpcsLayout = tabular.Layout{Kind: tabular.Fixed, MinLen: 11, Fields: []tabular.FixedField{
	{Name: "code", Start: 1, End: 5},
	{Name: "seq", Start: 6, End: 10},
	{Name: "ric", Start: 11, End: 11}, // record identification code
	{Name: "long", Start: 12, End: 91},
	{Name: "short", Start: 92, End: 119},
}}

var hcpcsName = regexp.MustCompile(`(?i)HCPC(\d{4})_([A-Z]{3})`)

var hcpcsQuarter = map[string]int{"JAN": 1, "APR": 4, "JUL": 7, "OCT": 10}

var HCPCS = register(&Format{
	Name:         "hcpcs-anweb",
	Title:        "HCPCS Level II alpha-numeric file (fixed-width text)",
	Publisher:    "CMS",
	Origin:       Vendor,
	CodeSystems:  []string{"hcpcs"},
	SourceFormat: "SOURCE_FORMAT_HCPCS_CMS",
	Files: []FileSpec{
		{ID: "anweb", Pattern: rx(`HCPC\d{4}_[A-Z]{3}_ANWEB[^/]*\.txt`), Required: true, Layout: hcpcsLayout},
	},
	Sniff: func(sel *Selection, md *Metadata, _ Options) {
		m := firstSubmatch(sel, hcpcsName)
		if m == nil {
			return
		}
		q := strings.ToUpper(m[2])
		md.Version = m[1] + "-" + q
		if month, ok := hcpcsQuarter[q]; ok {
			y, _ := strconv.Atoi(m[1])
			ey, em := y, month+3
			if em > 12 {
				ey, em = y+1, em-12
			}
			md.ReleaseDate = fmt.Sprintf("%d-%02d-01", y, month)
			md.ValiditySuggestion = fmt.Sprintf("[%d-%02d-01,%d-%02d-01)", y, month, ey, em)
		}
	},
	New: func(Options) Checker { return &hcpcsChecker{} },
})

var (
	hcpcsCode     = regexp.MustCompile(`^[A-Z][0-9]{4}$`)
	hcpcsModifier = regexp.MustCompile(`^[0-9A-Z]{2}$`)
)

type hcpcsChecker struct{ procedures, modifiers int64 }

func (h *hcpcsChecker) Row(c *Ctx, rec tabular.Record) {
	code := rec.Get("code")
	switch rec.Get("ric") {
	case "3":
		h.procedures++
		fallthrough
	case "4":
		if !hcpcsCode.MatchString(code) {
			c.Errorf(rec.Line, "bad_code", "%q is not a HCPCS Level II code", code)
		}
	case "7":
		h.modifiers++
		fallthrough
	case "8":
		if !hcpcsModifier.MatchString(code) {
			c.Errorf(rec.Line, "bad_code", "%q is not a HCPCS modifier", code)
		}
	default:
		c.Errorf(rec.Line, "bad_record_id", "record identification code %q is not 3, 4, 7 or 8", rec.Get("ric"))
	}
}

func (h *hcpcsChecker) Finish(c *Ctx) {
	c.Meta.AddCount("procedure codes", h.procedures)
	c.Meta.AddCount("modifiers", h.modifiers)
}

// ---- CPT (AMA data files) ----

var cptYear = regexp.MustCompile(`(?:^|[^0-9])(20\d{2})(?:[^0-9]|$)`)

var CPT = register(&Format{
	Name:         "cpt-ama",
	Title:        "CPT data files (LONGULT/MEDU/SHORTU + clinician and consumer descriptors)",
	Publisher:    "AMA",
	Origin:       Vendor,
	CodeSystems:  []string{"cpt"},
	SourceFormat: "SOURCE_FORMAT_CPT_AMA",
	// TODO(verify): code/description separator in the AMA text files (tab or space after the code).
	Files: []FileSpec{
		{ID: "long", Pattern: rx(`LONGULT\.txt`), Required: true},
		{ID: "medium", Pattern: rx(`MEDU\.txt`)},
		{ID: "short", Pattern: rx(`SHORTU\.txt`)},
		{ID: "clinician", Pattern: rx(`ClinicianDescriptor\.txt`), Layout: tabular.Layout{
			Kind: tabular.Delimited, Sep: "\t", Header: true, Required: []string{"Concept Id", "CPT Code", "Clinician Descriptor"}}},
		{ID: "consumer", Pattern: rx(`ConsumerDescriptor\.txt`), Layout: tabular.Layout{
			Kind: tabular.Delimited, Sep: "\t", Header: true, Required: []string{"Concept Id", "CPT Code", "Consumer Friendly Descriptor"}}},
	},
	Sniff: func(sel *Selection, md *Metadata, _ Options) {
		if m := firstSubmatch(sel, cptYear); m != nil {
			y, _ := strconv.Atoi(m[1])
			md.Version = m[1]
			md.ValiditySuggestion = fmt.Sprintf("[%d-01-01,%d-01-01)", y, y+1)
		}
	},
	New: func(Options) Checker { return &cptChecker{codes: map[string]struct{}{}} },
})

// CPT Category I codes are 5 digits; Category II end in F, Category III in T, PLA in U.
var cptCode = regexp.MustCompile(`^[0-9]{4}[0-9FTU]$`)

type cptChecker struct {
	codes map[string]struct{}
}

func (p *cptChecker) Stream(c *Ctx, r io.Reader) error {
	sc := bufio.NewScanner(r)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	var line int64
	for sc.Scan() {
		line++
		s := strings.TrimRight(sc.Text(), "\r")
		if strings.TrimSpace(s) == "" {
			continue
		}
		code, desc, ok := strings.Cut(s, "\t")
		if !ok {
			code, desc, ok = strings.Cut(s, " ")
		}
		code, desc = strings.TrimSpace(code), strings.TrimSpace(desc)
		AddRows(r, 1)
		if !ok || desc == "" {
			c.Errorf(line, "bad_line", "expected a code followed by a description")
			continue
		}
		if !cptCode.MatchString(code) {
			c.Errorf(line, "bad_code", "%q is not a CPT code", code)
		}
		if c.Spec.ID == "long" {
			p.codes[code] = struct{}{}
		} else if _, known := p.codes[code]; !known {
			c.Warnf(line, "unknown_code", "%s is not in LONGULT", code)
		}
	}
	return sc.Err()
}

func (p *cptChecker) Row(c *Ctx, rec tabular.Record) {
	code := rec.Get("CPT Code")
	if !cptCode.MatchString(code) {
		c.Errorf(rec.Line, "bad_code", "%q is not a CPT code", code)
	} else if _, known := p.codes[code]; !known {
		c.Warnf(rec.Line, "unknown_code", "%s is not in LONGULT", code)
	}
}

func (p *cptChecker) Finish(c *Ctx) { c.Meta.AddCount("codes", int64(len(p.codes))) }
