// SPDX-License-Identifier: GPL-3.0-or-later

// Package format knows the release formats the loader ingests. There are two kinds:
//
//   - vendor formats, the publisher's own distribution (SNOMED RF2, LOINC CSV, RxNorm RRF,
//     CMS ICD-10/HCPCS files, AMA CPT data files, CDC CVX/MVX, NUCC CSV, MedDRA ASCII,
//     FHIR CodeSystem JSON), and
//   - UMLS, the Metathesaurus RRF files, which hold many code systems and are filtered by
//     source abbreviation (SAB).
//
// A Format is mostly declarative: the files it expects (FileSpec: name pattern, layout,
// required or optional) plus a Checker that sees every row and reports issues. Validate
// streams every matched file once, so arbitrarily large releases (UMLS MRSAT) run in
// constant memory apart from the id sets a format keeps for referential checks.
//
// Ingest only verifies and describes a release. Mapping rows to the terms tables is the
// install step's job (PLAN M3/M6), which reuses these readers.
package format

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"regexp"
	"sort"
	"strings"

	"github.com/hlogue1/commonpoint/internal/terms/loader/source"
	"github.com/hlogue1/commonpoint/internal/terms/loader/tabular"
)

// Origin says who packaged the release.
type Origin string

const (
	Vendor Origin = "vendor"
	UMLS   Origin = "umls"
)

// Options tune one validation run.
type Options struct {
	// SAB restricts UMLS counts and checks to one source (e.g. "SNOMEDCT_US"). Empty means
	// the whole Metathesaurus.
	SAB string
}

// FileSpec is one kind of file in a release.
type FileSpec struct {
	ID      string
	Title   string
	Pattern *regexp.Regexp // matched against the slash-separated logical path in the source
	// Required: the release is incomplete without it.
	Required bool
	// OneOf: at least one spec of the group must match (e.g. ICD-10-CM order file or tabular XML).
	OneOf string
	// Multiple: more than one file may match (layered SNOMED packages, per-language RF2 files).
	Multiple bool
	// Layout is how to read it. A zero Kind means the format's Checker implements Streamer.
	Layout tabular.Layout
}

// Format describes one release format.
type Format struct {
	Name      string // CLI name, e.g. "snomed-rf2"
	Title     string
	Publisher string
	Origin    Origin
	// CodeSystems this format produces (code_system.id). Empty for UMLS, where the SAB decides.
	CodeSystems []string
	// SourceFormat is the AdminService SourceFormat enum value this maps to.
	SourceFormat string
	Files        []FileSpec
	// NoDetect excludes the format from auto-detection because its file names are too
	// generic (FHIR JSON); it must be named with --format.
	NoDetect bool
	// Sniff fills metadata cheaply from file names and small files, without a full scan.
	Sniff func(sel *Selection, md *Metadata, opts Options)
	// New returns a fresh Checker for one validation run.
	New func(opts Options) Checker
}

// Spec returns the spec with the given id.
func (f *Format) Spec(id string) *FileSpec {
	for i := range f.Files {
		if f.Files[i].ID == id {
			return &f.Files[i]
		}
	}
	return nil
}

// Checker receives every row of every tabular file, in spec order.
type Checker interface {
	Row(c *Ctx, rec tabular.Record)
	// Finish runs after all files; cross-file checks and metadata go here.
	Finish(c *Ctx)
}

// Streamer reads non-tabular files (XML, JSON). Returning an error records it as a
// file-level error.
type Streamer interface {
	Stream(c *Ctx, r io.Reader) error
}

// LayoutProvider lets a Checker override a spec's layout per file (UMLS MRFILES).
type LayoutProvider interface {
	Layout(spec *FileSpec, f *source.File) (tabular.Layout, bool)
}

// FileEnder is told when a file has been fully read.
type FileEnder interface {
	EndFile(c *Ctx, rows int64)
}

// Metadata is what a format can tell about a release.
type Metadata struct {
	Version        string `json:"version,omitempty"`
	ReleaseDate    string `json:"release_date,omitempty"` // YYYY-MM-DD
	FHIRVersionURI string `json:"fhir_version_uri,omitempty"`
	CodeSystemID   string `json:"code_system_id,omitempty"`
	CodeSystemURI  string `json:"code_system_uri,omitempty"`
	// ValiditySuggestion is a date-of-service range derived from the release name. It is
	// only a hint: the operator passes --validity explicitly.
	ValiditySuggestion string   `json:"validity_suggestion,omitempty"`
	Packages           []string `json:"packages,omitempty"`
	SABs               []SAB    `json:"sabs,omitempty"`
	Counts             []Count  `json:"counts,omitempty"`
	Notes              []string `json:"notes,omitempty"`
}

// SAB is one UMLS source from MRSAB.
type SAB struct {
	RSAB         string `json:"rsab"`
	VSAB         string `json:"vsab"`
	SVER         string `json:"sver"`
	Name         string `json:"name"`
	SRL          string `json:"srl"` // source restriction level, reported, not enforced here
	Language     string `json:"language"`
	Current      bool   `json:"current"`
	CodeSystemID string `json:"code_system_id,omitempty"`
}

// Count is a named statistic (e.g. "active concepts").
type Count struct {
	Name  string `json:"name"`
	Value int64  `json:"value"`
}

// AddCount appends a statistic.
func (m *Metadata) AddCount(name string, v int64) { m.Counts = append(m.Counts, Count{name, v}) }

// ---- registry ----

var registry []*Format

func register(f *Format) *Format {
	for _, g := range registry {
		if g.Name == f.Name {
			panic("format registered twice: " + f.Name)
		}
	}
	registry = append(registry, f)
	return f
}

// All returns every format, sorted by name.
func All() []*Format {
	out := append([]*Format(nil), registry...)
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// Lookup returns the named format or nil.
func Lookup(name string) *Format {
	for _, f := range registry {
		if strings.EqualFold(f.Name, name) {
			return f
		}
	}
	return nil
}

// ---- matching ----

// Selection is the files of a release assigned to a format's specs.
type Selection struct {
	Format    *Format
	Sources   []*source.Source
	Files     map[string][]*source.File // by spec id, in (source, name) order
	Unmatched []*source.File
}

// First returns the first file for a spec, or nil.
func (s *Selection) First(id string) *source.File {
	if fs := s.Files[id]; len(fs) > 0 {
		return fs[0]
	}
	return nil
}

// Match assigns source files to the format's specs and reports missing or ambiguous files.
func Match(f *Format, srcs []*source.Source) (*Selection, []Issue) {
	sel := &Selection{Format: f, Sources: srcs, Files: map[string][]*source.File{}}
	var issues []Issue
	for _, s := range srcs {
		for _, file := range s.Files() {
			matched := false
			for i := range f.Files {
				spec := &f.Files[i]
				if spec.Pattern.MatchString(file.Name) {
					sel.Files[spec.ID] = append(sel.Files[spec.ID], file)
					matched = true
					break
				}
			}
			if !matched {
				sel.Unmatched = append(sel.Unmatched, file)
				if strings.EqualFold(pathExt(file.Name), ".zip") {
					issues = append(issues, Issue{Severity: Warning, Code: "nested_archive", File: file.String(),
						Message: "archive inside a source is not read; extract it and pass it as its own source"})
				}
			}
		}
	}
	groups := map[string][]string{}
	groupHit := map[string]bool{}
	for _, spec := range f.Files {
		n := len(sel.Files[spec.ID])
		if spec.OneOf != "" {
			groups[spec.OneOf] = append(groups[spec.OneOf], spec.ID)
			if n > 0 {
				groupHit[spec.OneOf] = true
			}
		}
		if spec.Required && n == 0 {
			issues = append(issues, Issue{Severity: Error, Code: "missing_file",
				Message: fmt.Sprintf("required %s file not found (pattern %s)", spec.ID, spec.Pattern)})
		}
		if !spec.Multiple && n > 1 {
			var names []string
			for _, x := range sel.Files[spec.ID] {
				names = append(names, x.String())
			}
			issues = append(issues, Issue{Severity: Error, Code: "ambiguous_file",
				Message: fmt.Sprintf("%d files match %s; expected one: %s", n, spec.ID, strings.Join(names, ", "))})
		}
	}
	var gnames []string
	for g := range groups {
		gnames = append(gnames, g)
	}
	sort.Strings(gnames)
	for _, g := range gnames {
		if !groupHit[g] {
			issues = append(issues, Issue{Severity: Error, Code: "missing_file",
				Message: fmt.Sprintf("none of the %s files found; need one of: %s", g, strings.Join(groups[g], ", "))})
		}
	}
	return sel, issues
}

func pathExt(name string) string {
	if i := strings.LastIndexByte(name, '.'); i >= 0 && !strings.Contains(name[i:], "/") {
		return name[i:]
	}
	return ""
}

// Candidate is a format that fits a set of sources.
type Candidate struct {
	Format  *Format
	Matched int // number of matched files
}

// Detect returns the formats whose required files are all present, best match first.
func Detect(srcs []*source.Source) []Candidate {
	var out []Candidate
	for _, f := range All() {
		if f.NoDetect {
			continue
		}
		sel, issues := Match(f, srcs)
		if HasErrors(issues) {
			continue
		}
		n := 0
		for _, fs := range sel.Files {
			n += len(fs)
		}
		if n > 0 {
			out = append(out, Candidate{Format: f, Matched: n})
		}
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Matched > out[j].Matched })
	return out
}

// Sniff returns the metadata a format can derive without reading whole files.
func Sniff(sel *Selection, opts Options) Metadata {
	var md Metadata
	if sel.Format.Sniff != nil {
		sel.Format.Sniff(sel, &md, opts)
	}
	return md
}

// ---- validation ----

// FileResult describes one file after a full read.
type FileResult struct {
	Spec        string   `json:"spec"`
	Source      int      `json:"source"`
	Path        string   `json:"path"`
	Parts       []string `json:"parts,omitempty"` // only when split or compressed
	Bytes       int64    `json:"bytes"`           // decompressed
	SHA256      string   `json:"sha256"`          // of the decompressed content
	Encoding    string   `json:"encoding"`
	Rows        int64    `json:"rows"`
	Selected    *int64   `json:"selected_rows,omitempty"` // rows for the requested UMLS SAB
	InvalidUTF8 int64    `json:"invalid_utf8_lines,omitempty"`
}

// Ctx is passed to Checker callbacks.
type Ctx struct {
	Spec *FileSpec
	File *source.File
	Meta *Metadata
	Opts Options

	rep      *Report
	selected int64
	selects  bool
}

func (c *Ctx) fileName() string {
	if c.File == nil {
		return ""
	}
	return c.File.String()
}

// Errorf records an error at a line of the current file.
func (c *Ctx) Errorf(line int64, code, format string, args ...any) {
	c.rep.Add(Issue{Severity: Error, Code: code, File: c.fileName(), Line: line, Message: fmt.Sprintf(format, args...)})
}

// Warnf records a warning.
func (c *Ctx) Warnf(line int64, code, format string, args ...any) {
	c.rep.Add(Issue{Severity: Warning, Code: code, File: c.fileName(), Line: line, Message: fmt.Sprintf(format, args...)})
}

// Infof records an informational note.
func (c *Ctx) Infof(line int64, code, format string, args ...any) {
	c.rep.Add(Issue{Severity: Info, Code: code, File: c.fileName(), Line: line, Message: fmt.Sprintf(format, args...)})
}

// Select counts the current row as belonging to the requested UMLS SAB.
func (c *Ctx) Select() { c.selected++; c.selects = true }

// MarkSelecting reports selected_rows for this file even if no row matched.
func (c *Ctx) MarkSelecting() { c.selects = true }

// Validate reads every matched file once, in spec order, and returns the metadata and
// per-file results. Issues go to rep. Only I/O failures that stop the run return an error.
func Validate(ctx context.Context, sel *Selection, opts Options, rep *Report, progress func(FileResult)) (Metadata, []FileResult, error) {
	md := Sniff(sel, opts)
	ck := sel.Format.New(opts)
	var results []FileResult
	for i := range sel.Format.Files {
		spec := &sel.Format.Files[i]
		for _, file := range sel.Files[spec.ID] {
			if err := ctx.Err(); err != nil {
				return md, results, err
			}
			c := &Ctx{Spec: spec, File: file, Meta: &md, Opts: opts, rep: rep}
			res, err := readFile(ctx, c, ck)
			if err != nil {
				if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
					return md, results, err
				}
				c.Errorf(0, "read_failed", "%v", err)
			}
			if fe, ok := ck.(FileEnder); ok {
				fe.EndFile(c, res.Rows)
			}
			if c.selects {
				n := c.selected
				res.Selected = &n
			}
			results = append(results, res)
			if progress != nil {
				progress(res)
			}
		}
	}
	ck.Finish(&Ctx{Meta: &md, Opts: opts, rep: rep})
	return md, results, nil
}

type countingWriter struct{ n int64 }

func (w *countingWriter) Write(p []byte) (int, error) { w.n += int64(len(p)); return len(p), nil }

func readFile(ctx context.Context, c *Ctx, ck Checker) (FileResult, error) {
	file := c.File
	res := FileResult{Spec: c.Spec.ID, Source: file.Source.Index, Path: file.Name}
	if parts := file.Parts(); len(parts) > 1 || parts[0] != file.Name {
		res.Parts = parts
	}
	rc, err := file.Open()
	if err != nil {
		return res, err
	}
	defer rc.Close()
	h := sha256.New()
	cw := &countingWriter{}
	tee := io.TeeReader(rc, io.MultiWriter(h, cw))
	r, enc := source.Decode(tee)
	res.Encoding = string(enc)

	finish := func() error {
		// Hash the whole file even if parsing stopped early.
		if _, err := io.Copy(io.Discard, r); err != nil {
			return err
		}
		res.Bytes = cw.n
		res.SHA256 = hex.EncodeToString(h.Sum(nil))
		return nil
	}

	layout := c.Spec.Layout
	if lp, ok := ck.(LayoutProvider); ok {
		if l, ok := lp.Layout(c.Spec, file); ok {
			layout = l
		}
	}
	if layout.Kind == 0 {
		st, ok := ck.(Streamer)
		if !ok {
			return res, fmt.Errorf("no reader for %s files", c.Spec.ID)
		}
		cr := &rowCounter{r: r}
		if err := st.Stream(c, cr); err != nil {
			c.Errorf(0, "parse_failed", "%v", err)
		}
		res.Rows = cr.rows
		return res, finish()
	}

	rd, err := tabular.NewReader(r, layout)
	if err != nil {
		var he *tabular.HeaderError
		if errors.As(err, &he) {
			c.Errorf(1, "bad_header", "%s", he.Msg)
			return res, finish()
		}
		return res, err
	}
	for {
		rec, err := rd.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			var re *tabular.RowError
			if errors.As(err, &re) {
				c.Errorf(re.Line, re.Code, "%s", re.Msg)
				continue
			}
			var he *tabular.HeaderError
			if errors.As(err, &he) {
				c.Errorf(rd.Line(), "unreadable", "%s", he.Msg)
				break
			}
			return res, err
		}
		res.Rows++
		if res.Rows%65536 == 0 {
			if err := ctx.Err(); err != nil {
				return res, err
			}
		}
		ck.Row(c, rec)
	}
	res.InvalidUTF8 = rd.InvalidUTF8Lines()
	if res.InvalidUTF8 > 0 {
		c.Warnf(0, "invalid_utf8", "%d lines are not valid UTF-8", res.InvalidUTF8)
	}
	return res, finish()
}

// rowCounter lets streamers report a row count via Ctx without extra plumbing.
type rowCounter struct {
	r    io.Reader
	rows int64
}

func (rc *rowCounter) Read(p []byte) (int, error) { return rc.r.Read(p) }

// AddRows lets a Streamer report how many records it read.
func AddRows(r io.Reader, n int64) {
	if rc, ok := r.(*rowCounter); ok {
		rc.rows += n
	}
}
