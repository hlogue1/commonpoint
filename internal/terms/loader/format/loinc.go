// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"regexp"
	"strconv"
	"strings"

	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

func csvLayout(required ...string) tabular.Layout {
	return tabular.Layout{Kind: tabular.CSV, Header: true, Required: required}
}

var loincVersionName = regexp.MustCompile(`(?i)Loinc_(\d+\.\d+)`)

var LoincCSV = register(&Format{
	Name:         "loinc-csv",
	Title:        "LOINC table and accessory files (CSV)",
	Publisher:    "Regenstrief Institute",
	Origin:       Vendor,
	CodeSystems:  []string{"loinc"},
	SourceFormat: "SOURCE_FORMAT_LOINC_CSV",
	Files: []FileSpec{
		{ID: "loinc", Pattern: rx(`Loinc\.csv`), Required: true, Layout: csvLayout(
			"LOINC_NUM", "COMPONENT", "PROPERTY", "TIME_ASPCT", "SYSTEM", "SCALE_TYP", "METHOD_TYP",
			"CLASS", "CLASSTYPE", "STATUS", "SHORTNAME", "LONG_COMMON_NAME", "VersionLastChanged")},
		{ID: "map_to", Pattern: rx(`MapTo\.csv`), Layout: csvLayout("LOINC", "MAP_TO")},
		{ID: "answer_list", Pattern: rx(`AnswerList\.csv`), Layout: csvLayout("AnswerListId", "AnswerListName", "AnswerStringId", "SequenceNumber", "DisplayText")},
		{ID: "answer_list_link", Pattern: rx(`LoincAnswerListLink\.csv`), Layout: csvLayout("LoincNumber", "AnswerListId", "AnswerListLinkType")},
		{ID: "panels", Pattern: rx(`PanelsAndForms\.csv`), Layout: csvLayout("ParentLoinc", "Loinc", "SEQUENCE")},
		{ID: "component_hierarchy", Pattern: rx(`ComponentHierarchyBySystem\.csv`), Layout: csvLayout("PATH_TO_ROOT", "SEQUENCE", "IMMEDIATE_PARENT", "CODE", "CODE_TEXT")},
	},
	Sniff: func(sel *Selection, md *Metadata, _ Options) {
		if m := firstSubmatch(sel, loincVersionName); m != nil {
			md.Version = m[1]
		}
	},
	New: func(Options) Checker { return &loincChecker{codes: map[string]struct{}{}} },
})

var loincStatus = map[string]bool{"ACTIVE": true, "TRIAL": true, "DISCOURAGED": true, "DEPRECATED": true}

type loincChecker struct {
	codes      map[string]struct{}
	active     int64
	maxVersion string
}

func (l *loincChecker) code(c *Ctx, rec tabular.Record, col string, mustExist bool) {
	v := rec.Get(col)
	if v == "" {
		return
	}
	if !LOINCValid(v) {
		c.Errorf(rec.Line, "bad_loinc", "%s %q is not a LOINC code with a valid check digit", col, v)
		return
	}
	if mustExist && !strings.HasPrefix(v, "LP") {
		if _, ok := l.codes[v]; !ok {
			c.Warnf(rec.Line, "unknown_loinc", "%s %s is not in Loinc.csv", col, v)
		}
	}
}

func (l *loincChecker) Row(c *Ctx, rec tabular.Record) {
	switch c.Spec.ID {
	case "loinc":
		v := rec.Get("LOINC_NUM")
		if !LOINCValid(v) {
			c.Errorf(rec.Line, "bad_loinc", "LOINC_NUM %q is not a LOINC code with a valid check digit", v)
		}
		if _, dup := l.codes[v]; dup {
			c.Errorf(rec.Line, "duplicate_code", "LOINC_NUM %s appears more than once", v)
		}
		l.codes[v] = struct{}{}
		st := rec.Get("STATUS")
		if !loincStatus[st] {
			c.Warnf(rec.Line, "unknown_status", "STATUS %q is not one of ACTIVE, TRIAL, DISCOURAGED, DEPRECATED", st)
		}
		if st == "ACTIVE" {
			l.active++
		}
		if ct := rec.Get("CLASSTYPE"); ct < "1" || ct > "4" || len(ct) != 1 {
			c.Warnf(rec.Line, "unknown_classtype", "CLASSTYPE %q is not 1-4", ct)
		}
		if rec.Get("LONG_COMMON_NAME") == "" {
			c.Warnf(rec.Line, "empty_name", "LOINC %s has no LONG_COMMON_NAME", v)
		}
		if lv := rec.Get("VersionLastChanged"); versionLess(l.maxVersion, lv) {
			l.maxVersion = lv
		}
	case "map_to":
		l.code(c, rec, "LOINC", true)
		l.code(c, rec, "MAP_TO", true)
	case "answer_list":
		// Externally defined lists use their own ids; only LOINC LL/LA ids are checked.
		if id := rec.Get("AnswerListId"); strings.HasPrefix(id, "LL") && !LOINCValid(id) {
			c.Errorf(rec.Line, "bad_answer_list", "AnswerListId %q is not an LL code", id)
		}
		if a := rec.Get("AnswerStringId"); a != "" && !LOINCValid(a) {
			c.Errorf(rec.Line, "bad_answer", "AnswerStringId %q is not an LA code", a)
		}
	case "answer_list_link":
		l.code(c, rec, "LoincNumber", true)
	case "panels":
		l.code(c, rec, "ParentLoinc", true)
		l.code(c, rec, "Loinc", true)
	}
}

func (l *loincChecker) Finish(c *Ctx) {
	c.Meta.AddCount("terms", int64(len(l.codes)))
	c.Meta.AddCount("active terms", l.active)
	if c.Meta.Version == "" && l.maxVersion != "" {
		c.Meta.Version = l.maxVersion
		c.Meta.Notes = append(c.Meta.Notes, "version taken from the highest VersionLastChanged")
	}
}

// versionLess compares dotted numeric versions ("2.9" < "2.10").
func versionLess(a, b string) bool {
	if a == "" {
		return b != ""
	}
	as, bs := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < len(as) || i < len(bs); i++ {
		var x, y int
		if i < len(as) {
			x, _ = strconv.Atoi(as[i])
		}
		if i < len(bs) {
			y, _ = strconv.Atoi(bs[i])
		}
		if x != y {
			return x < y
		}
	}
	return false
}
