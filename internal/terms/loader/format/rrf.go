// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/hlogue1/commonpoint/internal/terms/loader/source"
	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

// RRF ("Rich Release Format") is pipe-delimited with a trailing pipe and no header. The
// column lists below are the documented defaults; a UMLS release's MRFILES.RRF overrides them.

func rrf(cols ...string) tabular.Layout {
	return tabular.Layout{Kind: tabular.Delimited, Sep: "|", Columns: cols}
}

var mrsabCols = []string{"VCUI", "RCUI", "VSAB", "RSAB", "SON", "SF", "SVER", "VSTART", "VEND", "IMETA", "RMETA",
	"SLC", "SCC", "SRL", "TFR", "CFR", "CXTY", "TTYL", "ATNL", "LAT", "CENC", "CURVER", "SABIN", "SSN", "SCIT"}

// ---- RxNorm (NLM's own RxNorm release) ----

var rxnormDate = regexp.MustCompile(`(?i)RxNorm_full_(?:prescribe_)?(\d{2})(\d{2})(\d{4})`)

var RxNormRRF = register(&Format{
	Name:         "rxnorm-rrf",
	Title:        "RxNorm full monthly release (RXN*.RRF)",
	Publisher:    "NLM",
	Origin:       Vendor,
	CodeSystems:  []string{"rxnorm"},
	SourceFormat: "SOURCE_FORMAT_RXNORM_RRF",
	Files: []FileSpec{
		{ID: "rxnsab", Pattern: rx(`RXNSAB\.RRF`), Layout: rrf(mrsabCols...)},
		{ID: "rxnconso", Pattern: rx(`RXNCONSO\.RRF`), Required: true, Layout: rrf(
			"RXCUI", "LAT", "TS", "LUI", "STT", "SUI", "ISPREF", "RXAUI", "SAUI", "SCUI", "SDUI", "SAB", "TTY", "CODE", "STR", "SRL", "SUPPRESS", "CVF")},
		{ID: "rxnrel", Pattern: rx(`RXNREL\.RRF`), Required: true, Layout: rrf(
			"RXCUI1", "RXAUI1", "STYPE1", "REL", "RXCUI2", "RXAUI2", "STYPE2", "RELA", "RUI", "SRUI", "SAB", "SL", "DIR", "RG", "SUPPRESS", "CVF")},
		{ID: "rxnsat", Pattern: rx(`RXNSAT\.RRF`), Required: true, Layout: rrf(
			"RXCUI", "LUI", "SUI", "RXAUI", "STYPE", "CODE", "ATUI", "SATUI", "ATN", "SAB", "ATV", "SUPPRESS", "CVF")},
		{ID: "rxnsty", Pattern: rx(`RXNSTY\.RRF`), Layout: rrf("RXCUI", "TUI", "STN", "STY", "ATUI", "CVF")},
		{ID: "rxndoc", Pattern: rx(`RXNDOC\.RRF`), Layout: rrf("DOCKEY", "VALUE", "TYPE", "EXPL")},
		{ID: "rxncui", Pattern: rx(`RXNCUI\.RRF`), Layout: rrf("CUI1", "VER_START", "VER_END", "CARDINALITY", "CUI2")},
		{ID: "rxncuichanges", Pattern: rx(`RXNCUICHANGES\.RRF`), Layout: rrf("RXAUI", "CODE", "SAB", "TTY", "STR", "OLD_RXCUI", "NEW_RXCUI")},
		{ID: "rxnatomarchive", Pattern: rx(`RXNATOMARCHIVE\.RRF`), Layout: rrf(
			"RXAUI", "AUI", "STR", "ARCHIVE_TIMESTAMP", "CREATED_TIMESTAMP", "UPDATED_TIMESTAMP", "CODE", "IS_BRAND",
			"LAT", "LAST_RELEASED", "SAUI", "VSAB", "RXCUI", "SAB", "TTY", "MERGED_TO_RXCUI")},
	},
	Sniff: func(sel *Selection, md *Metadata, _ Options) {
		if m := firstSubmatch(sel, rxnormDate); m != nil {
			md.Version = m[1] + m[2] + m[3] // NLM labels releases MMDDYYYY
			md.ReleaseDate = m[3] + "-" + m[1] + "-" + m[2]
		}
	},
	New: func(Options) Checker { return &rxnormChecker{} },
})

type rxnormChecker struct {
	rxnormAtoms, rxcuis int64
	lastCUI             string
}

func (r *rxnormChecker) Row(c *Ctx, rec tabular.Record) {
	switch c.Spec.ID {
	case "rxnsab":
		if rec.Get("RSAB") == "RXNORM" && rec.Get("CURVER") == "Y" {
			c.Meta.Notes = append(c.Meta.Notes, "RXNSAB RXNORM SVER "+rec.Get("SVER"))
		}
	case "rxnconso":
		cui := rec.Get("RXCUI")
		if !isDigits(cui) {
			c.Errorf(rec.Line, "bad_rxcui", "RXCUI %q is not numeric", cui)
		}
		if rec.Get("SAB") == "" || rec.Get("TTY") == "" {
			c.Errorf(rec.Line, "missing_field", "SAB and TTY are required")
		}
		if rec.Get("SAB") == "RXNORM" {
			r.rxnormAtoms++
		}
		if cui != r.lastCUI {
			r.rxcuis++ // RXNCONSO is sorted by RXCUI
			r.lastCUI = cui
		}
	case "rxnrel":
		if rec.Get("RXCUI1") == "" && rec.Get("RXAUI1") == "" {
			c.Errorf(rec.Line, "missing_field", "a relationship needs RXCUI1 or RXAUI1")
		}
	case "rxnsat":
		if cui := rec.Get("RXCUI"); cui != "" && !isDigits(cui) {
			c.Errorf(rec.Line, "bad_rxcui", "RXCUI %q is not numeric", cui)
		}
	}
}

func (r *rxnormChecker) Finish(c *Ctx) {
	c.Meta.AddCount("RXNORM atoms", r.rxnormAtoms)
	c.Meta.AddCount("distinct RXCUI runs", r.rxcuis)
	if r.rxnormAtoms == 0 {
		c.Errorf(0, "no_rxnorm_atoms", "RXNCONSO has no SAB=RXNORM rows")
	}
}

// ---- UMLS Metathesaurus ----

var umlsRelease = regexp.MustCompile(`(?i)(?:^|[/_-])(\d{4}A[AB])(?:[/_-]|$)`)

// umlsFiles are the Metathesaurus files ingest reads. MRFILES comes first so its column
// definitions apply to the rest; MRSAB second so the SAB filter can be checked against it.
var umlsFiles = []FileSpec{
	{ID: "MRFILES", Pattern: rx(`MRFILES\.RRF`), Layout: rrf("FIL", "DES", "FMT", "CLS", "RWS", "BTS")},
	{ID: "MRSAB", Pattern: rx(`MRSAB\.RRF`), Required: true, Layout: rrf(mrsabCols...)},
	{ID: "MRCONSO", Pattern: rx(`MRCONSO\.RRF`), Required: true, Layout: rrf(
		"CUI", "LAT", "TS", "LUI", "STT", "SUI", "ISPREF", "AUI", "SAUI", "SCUI", "SDUI", "SAB", "TTY", "CODE", "STR", "SRL", "SUPPRESS", "CVF")},
	{ID: "MRREL", Pattern: rx(`MRREL\.RRF`), Layout: rrf(
		"CUI1", "AUI1", "STYPE1", "REL", "CUI2", "AUI2", "STYPE2", "RELA", "RUI", "SRUI", "SAB", "SL", "RG", "DIR", "SUPPRESS", "CVF")},
	{ID: "MRSAT", Pattern: rx(`MRSAT\.RRF`), Layout: rrf(
		"CUI", "LUI", "SUI", "METAUI", "STYPE", "CODE", "ATUI", "SATUI", "ATN", "SAB", "ATV", "SUPPRESS", "CVF")},
	{ID: "MRDEF", Pattern: rx(`MRDEF\.RRF`), Layout: rrf("CUI", "AUI", "ATUI", "SATUI", "SAB", "DEF", "SUPPRESS", "CVF")},
	{ID: "MRSTY", Pattern: rx(`MRSTY\.RRF`), Layout: rrf("CUI", "TUI", "STN", "STY", "ATUI", "CVF")},
	{ID: "MRHIER", Pattern: rx(`MRHIER\.RRF`), Layout: rrf("CUI", "AUI", "CXN", "PAUI", "SAB", "RELA", "PTR", "HCD", "CVF")},
	{ID: "MRRANK", Pattern: rx(`MRRANK\.RRF`), Layout: rrf("RANK", "SAB", "TTY", "SUPPRESS")},
}

var UMLSRRF = register(&Format{
	Name:         "umls-rrf",
	Title:        "UMLS Metathesaurus RRF (MR*.RRF), filtered by source abbreviation (SAB)",
	Publisher:    "NLM",
	Origin:       UMLS,
	SourceFormat: "SOURCE_FORMAT_UMLS_RRF",
	Files:        umlsFiles,
	Sniff:        sniffUMLS,
	New:          func(o Options) Checker { return &umlsChecker{opts: o, mrfiles: map[string]mrfile{}} },
})

func sniffUMLS(sel *Selection, md *Metadata, opts Options) {
	if m := firstSubmatch(sel, umlsRelease); m != nil {
		md.Notes = append(md.Notes, "UMLS release "+strings.ToUpper(m[1]))
		if opts.SAB == "" {
			md.Version = strings.ToUpper(m[1])
		}
	}
	f := sel.First("MRSAB")
	if f == nil {
		return
	}
	sabs, err := ReadMRSAB(f)
	if err != nil {
		md.Notes = append(md.Notes, "MRSAB unreadable: "+err.Error())
		return
	}
	md.SABs = sabs
	applySAB(md, opts)
}

// ReadMRSAB reads the source list of a Metathesaurus release (a small file).
func ReadMRSAB(f *source.File) ([]SAB, error) {
	rc, err := f.Open()
	if err != nil {
		return nil, err
	}
	defer rc.Close()
	r, _ := source.Decode(rc)
	rd, err := tabular.NewReader(r, rrf(mrsabCols...))
	if err != nil {
		return nil, err
	}
	var out []SAB
	for {
		rec, err := rd.Next()
		if err != nil {
			if _, ok := err.(*tabular.RowError); ok {
				continue
			}
			break
		}
		s := SAB{RSAB: rec.Get("RSAB"), VSAB: rec.Get("VSAB"), SVER: rec.Get("SVER"), Name: rec.Get("SON"),
			SRL: rec.Get("SRL"), Language: rec.Get("LAT"), Current: rec.Get("CURVER") == "Y"}
		if cs := CodeSystemForSAB(s.RSAB); cs != nil {
			s.CodeSystemID = cs.ID
		}
		out = append(out, s)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].RSAB != out[j].RSAB {
			return out[i].RSAB < out[j].RSAB
		}
		return out[i].VSAB < out[j].VSAB
	})
	return out, nil
}

func applySAB(md *Metadata, opts Options) {
	if opts.SAB == "" {
		return
	}
	for _, s := range md.SABs {
		if strings.EqualFold(s.RSAB, opts.SAB) && s.Current {
			md.Version = s.SVER
			md.CodeSystemID = s.CodeSystemID
			md.Notes = append(md.Notes, fmt.Sprintf("SAB %s: %s (VSAB %s, source restriction level %s)", s.RSAB, s.Name, s.VSAB, s.SRL))
			return
		}
	}
}

type mrfile struct {
	cols []string
	rows int64
}

type umlsChecker struct {
	opts      Options
	mrfiles   map[string]mrfile
	sabFound  bool
	sabCurver bool
	consoSAB  int64 // MRCONSO rows for the requested SAB
}

var cuiRe = regexp.MustCompile(`^C\d{7}$`)

// Layout applies MRFILES column definitions to the file being read.
func (u *umlsChecker) Layout(spec *FileSpec, f *source.File) (tabular.Layout, bool) {
	if spec.ID == "MRFILES" {
		return tabular.Layout{}, false
	}
	m, ok := u.mrfiles[strings.ToUpper(f.Base())]
	if !ok {
		return tabular.Layout{}, false
	}
	return rrf(m.cols...), true
}

func (u *umlsChecker) Row(c *Ctx, rec tabular.Record) {
	sab := rec.Get("SAB")
	if c.Spec.ID != "MRFILES" && c.Spec.ID != "MRSAB" && rec.Has("SAB") && u.opts.SAB != "" {
		c.MarkSelecting()
		if strings.EqualFold(sab, u.opts.SAB) {
			c.Select()
			if c.Spec.ID == "MRCONSO" {
				u.consoSAB++
			}
		}
	}
	switch c.Spec.ID {
	case "MRFILES":
		name := strings.ToUpper(rec.Get("FIL"))
		rows, _ := strconv.ParseInt(rec.Get("RWS"), 10, 64)
		u.mrfiles[name] = mrfile{cols: strings.Split(rec.Get("FMT"), ","), rows: rows}
	case "MRSAB":
		if u.opts.SAB != "" && strings.EqualFold(rec.Get("RSAB"), u.opts.SAB) {
			u.sabFound = true
			if rec.Get("CURVER") == "Y" {
				u.sabCurver = true
			}
		}
	case "MRCONSO":
		if !cuiRe.MatchString(rec.Get("CUI")) {
			c.Errorf(rec.Line, "bad_cui", "CUI %q is not C + 7 digits", rec.Get("CUI"))
		}
		if ts := rec.Get("TS"); ts != "P" && ts != "S" {
			c.Errorf(rec.Line, "bad_field", "TS %q is not P or S", ts)
		}
		if s := rec.Get("SUPPRESS"); s != "N" && s != "O" && s != "E" && s != "Y" {
			c.Errorf(rec.Line, "bad_field", "SUPPRESS %q is not N, O, E or Y", s)
		}
		if sab == "" || rec.Get("STR") == "" {
			c.Errorf(rec.Line, "missing_field", "SAB and STR are required")
		}
	default:
		if cui := rec.Get("CUI"); cui != "" && !cuiRe.MatchString(cui) {
			c.Errorf(rec.Line, "bad_cui", "CUI %q is not C + 7 digits", cui)
		}
	}
}

// EndFile checks the row count against MRFILES.
func (u *umlsChecker) EndFile(c *Ctx, rows int64) {
	if c.Spec.ID == "MRFILES" {
		return
	}
	if m, ok := u.mrfiles[strings.ToUpper(c.File.Base())]; ok && m.rows != rows {
		c.Errorf(0, "row_count", "MRFILES says %d rows; read %d", m.rows, rows)
	}
}

func (u *umlsChecker) Finish(c *Ctx) {
	if u.opts.SAB == "" {
		return
	}
	if !u.sabFound {
		c.Errorf(0, "unknown_sab", "SAB %s is not in MRSAB", u.opts.SAB)
	} else if !u.sabCurver {
		c.Errorf(0, "sab_not_current", "SAB %s has no current version (CURVER=Y) in MRSAB", u.opts.SAB)
	}
	c.Meta.AddCount("MRCONSO rows for "+u.opts.SAB, u.consoSAB)
	if u.sabFound && u.consoSAB == 0 {
		c.Errorf(0, "empty_sab", "MRCONSO has no rows for SAB %s (was it excluded from the subset?)", u.opts.SAB)
	}
}
