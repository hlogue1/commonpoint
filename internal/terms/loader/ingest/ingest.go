// SPDX-License-Identifier: GPL-3.0-or-later

// Package ingest verifies a terminology release before it's registered. It checks source
// SHA-256 values, resolves the format (vendor or UMLS) and code system, reads every file
// once to validate it, reconciles the version metadata, and produces a Manifest.
//
// The manifest carries the fields of AdminService.StartIngestRequest plus per-file
// checksums and counts. It's deterministic (no timestamps, sorted), so the same release gives
// a byte-identical manifest on any machine (CLAUDE rule 7). Promotion between terminology
// environments is a separate ETL and isn't handled here.
package ingest

import (
	"context"
	"encoding/hex"
	"fmt"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/hlogue1/commonpoint/internal/terms/loader/format"
	"github.com/hlogue1/commonpoint/internal/terms/loader/source"
)

// ManifestVersion is bumped on incompatible manifest changes.
const ManifestVersion = 1

// Request is one ingest. Empty fields are derived from the release where possible.
type Request struct {
	CodeSystemID   string
	Format         string // format name; empty = detect
	SAB            string // UMLS only
	Version        string
	ReleaseDate    string // YYYY-MM-DD
	FHIRVersionURI string
	Validity       string // "[2026-10-01,2027-10-01)"
	Sources        []string
	SHA256         []string // expected, same order as Sources; optional
	Reason         string
	// IngestDir: source paths in the manifest are made relative to it (the server resolves
	// StartIngestRequest.sources against its own ingest directory).
	IngestDir string
	// MaxIssues per (severity, file, code); 0 keeps all.
	MaxIssues int
	// Progress is called after each file is read.
	Progress func(format.FileResult)
}

// Source is one source in the manifest.
type Source struct {
	Path   string      `json:"path"`
	Kind   source.Kind `json:"kind"`
	Bytes  int64       `json:"bytes"`
	SHA256 string      `json:"sha256"`
}

// Manifest is the result of an ingest.
type Manifest struct {
	ManifestVersion int    `json:"manifest_version"`
	OK              bool   `json:"ok"`
	CodeSystemID    string `json:"code_system_id"`
	Format          string `json:"format"`
	Origin          string `json:"origin"`
	SourceFormat    string `json:"source_format"` // AdminService SourceFormat enum
	SAB             string `json:"umls_sab,omitempty"`
	Version         string `json:"version"`
	ReleaseDate     string `json:"release_date,omitempty"`
	FHIRVersionURI  string `json:"fhir_version_uri,omitempty"`
	Validity        string `json:"validity,omitempty"`
	Reason          string `json:"reason,omitempty"`

	Sources    []Source            `json:"sources"`
	Detected   format.Metadata     `json:"detected"`
	Files      []format.FileResult `json:"files"`
	Ignored    []string            `json:"ignored_files,omitempty"`
	Errors     int64               `json:"errors"`
	Warnings   int64               `json:"warnings"`
	Issues     []format.Issue      `json:"issues"`
	Suppressed []format.Suppressed `json:"suppressed,omitempty"`
}

// Run executes the ingest checks. It returns an error only when the run itself couldn't
// proceed (unreadable source, cancelled); problems with the release are issues in the
// manifest, and Manifest.OK is false if any is an error.
func Run(ctx context.Context, req Request) (*Manifest, error) {
	rep := format.NewReport(req.MaxIssues)
	m := &Manifest{ManifestVersion: ManifestVersion, Reason: req.Reason}
	finish := func() *Manifest {
		m.Errors, m.Warnings = rep.Errors, rep.Warnings
		m.Issues = rep.Issues
		m.Suppressed = rep.Suppressed()
		m.OK = rep.Errors == 0
		return m
	}

	if len(req.Sources) == 0 {
		return nil, fmt.Errorf("no sources given")
	}
	if len(req.SHA256) > 0 && len(req.SHA256) != len(req.Sources) {
		return nil, fmt.Errorf("%d --sha256 values for %d sources; give one per source, in order", len(req.SHA256), len(req.Sources))
	}

	// 1. Open and checksum every source. A mismatch stops here, before anything is parsed.
	var srcs []*source.Source
	defer func() {
		for _, s := range srcs {
			_ = s.Close()
		}
	}()
	for i, p := range req.Sources {
		s, err := source.Open(p, i)
		if err != nil {
			return nil, fmt.Errorf("source %d: %w", i, err)
		}
		srcs = append(srcs, s)
		sum, err := s.SHA256()
		if err != nil {
			return nil, fmt.Errorf("checksum %s: %w", p, err)
		}
		s.Label = manifestPath(req.IngestDir, p)
		m.Sources = append(m.Sources, Source{Path: s.Label, Kind: s.Kind, Bytes: s.Size, SHA256: sum})
		if len(req.SHA256) > 0 {
			want := strings.ToLower(strings.TrimSpace(req.SHA256[i]))
			if _, err := hex.DecodeString(want); err != nil || len(want) != 64 {
				rep.Add(format.Issue{Severity: format.Error, Code: "bad_checksum_arg", File: s.Label, Message: fmt.Sprintf("%q is not a SHA-256 hex digest", req.SHA256[i])})
			} else if want != sum {
				rep.Add(format.Issue{Severity: format.Error, Code: "checksum_mismatch", File: s.Label,
					Message: fmt.Sprintf("SHA-256 is %s; expected %s", sum, want)})
			}
		}
	}
	if rep.Errors > 0 {
		return finish(), nil
	}

	// 2. Format.
	f, err := resolveFormat(req, srcs, rep)
	if err != nil {
		return nil, err
	}
	if f == nil {
		return finish(), nil
	}
	m.Format, m.Origin, m.SourceFormat = f.Name, string(f.Origin), f.SourceFormat

	// 3. Code system and UMLS SAB.
	opts := format.Options{}
	m.CodeSystemID, opts.SAB = resolveCodeSystem(req, f, rep)
	m.SAB = opts.SAB

	// 4. Match files.
	sel, issues := format.Match(f, srcs)
	rep.AddAll(issues)
	for _, u := range sel.Unmatched {
		m.Ignored = append(m.Ignored, fmt.Sprintf("%d:%s", u.Source.Index, u.Name))
	}
	if format.HasErrors(issues) {
		m.Detected = format.Sniff(sel, opts)
		reconcile(m, req, rep)
		return finish(), nil
	}

	// 5. Read and validate everything.
	md, results, err := format.Validate(ctx, sel, opts, rep, req.Progress)
	if err != nil {
		return nil, err
	}
	m.Detected, m.Files = md, results
	if m.CodeSystemID == "" && md.CodeSystemID != "" {
		m.CodeSystemID = md.CodeSystemID
	}

	// 6. Version metadata and code system rules.
	reconcile(m, req, rep)
	return finish(), nil
}

func manifestPath(ingestDir, p string) string {
	if ingestDir != "" {
		absDir, err1 := filepath.Abs(ingestDir)
		absP, err2 := filepath.Abs(p)
		if err1 == nil && err2 == nil {
			if rel, err := filepath.Rel(absDir, absP); err == nil && !strings.HasPrefix(rel, "..") {
				return filepath.ToSlash(rel)
			}
		}
	}
	return filepath.ToSlash(filepath.Clean(p))
}

func resolveFormat(req Request, srcs []*source.Source, rep *format.Report) (*format.Format, error) {
	if req.Format != "" {
		f := format.Lookup(req.Format)
		if f == nil {
			return nil, fmt.Errorf("unknown format %q (see `ctl terms formats`)", req.Format)
		}
		return f, nil
	}
	cands := format.Detect(srcs)
	switch {
	case len(cands) == 0:
		rep.Add(format.Issue{Severity: format.Error, Code: "unknown_format",
			Message: "no known release format matches these sources; pass --format (see `ctl terms formats`)"})
		return nil, nil
	case len(cands) > 1 && cands[0].Matched == cands[1].Matched:
		var names []string
		for _, c := range cands {
			names = append(names, c.Format.Name)
		}
		rep.Add(format.Issue{Severity: format.Error, Code: "ambiguous_format",
			Message: "sources match several formats equally well (" + strings.Join(names, ", ") + "); pass --format"})
		return nil, nil
	}
	if req.CodeSystemID != "" {
		// Prefer a candidate that produces the requested code system.
		for _, c := range cands {
			for _, cs := range c.Format.CodeSystems {
				if strings.EqualFold(cs, req.CodeSystemID) {
					return c.Format, nil
				}
			}
		}
	}
	return cands[0].Format, nil
}

func resolveCodeSystem(req Request, f *format.Format, rep *format.Report) (string, string) {
	id, sab := strings.ToLower(req.CodeSystemID), strings.ToUpper(req.SAB)
	if id != "" && format.LookupCodeSystem(id) == nil {
		rep.Add(format.Issue{Severity: format.Error, Code: "unknown_code_system", Message: fmt.Sprintf("code system %q is not in the catalog", id)})
	}
	if f.Origin != format.UMLS {
		if sab != "" {
			rep.Add(format.Issue{Severity: format.Error, Code: "sab_not_umls", Message: "--sab applies only to the umls-rrf format"})
		}
		if id == "" && len(f.CodeSystems) == 1 {
			id = f.CodeSystems[0]
		}
		if id != "" && len(f.CodeSystems) > 0 && !contains(f.CodeSystems, id) {
			rep.Add(format.Issue{Severity: format.Error, Code: "format_system_mismatch",
				Message: fmt.Sprintf("format %s produces %s, not %s", f.Name, strings.Join(f.CodeSystems, ", "), id)})
		}
		return id, ""
	}
	// UMLS: the SAB names the source; the code system follows from it, or vice versa.
	switch {
	case sab == "" && id == "":
		rep.Add(format.Issue{Severity: format.Error, Code: "missing_sab",
			Message: "umls-rrf needs --sab or --system (use --system umls for the whole Metathesaurus)"})
	case sab == "" && id == "umls":
	case sab == "":
		cs := format.LookupCodeSystem(id)
		if cs == nil || len(cs.SABs) == 0 {
			rep.Add(format.Issue{Severity: format.Error, Code: "missing_sab", Message: fmt.Sprintf("no UMLS SAB is known for %s; pass --sab", id)})
		} else {
			sab = cs.SABs[0]
		}
	case id == "":
		if cs := format.CodeSystemForSAB(sab); cs != nil {
			id = cs.ID
		} else {
			rep.Add(format.Issue{Severity: format.Error, Code: "unmapped_sab",
				Message: fmt.Sprintf("SAB %s doesn't map to a code system; pass --system", sab)})
		}
	default:
		if cs := format.CodeSystemForSAB(sab); cs != nil && !strings.EqualFold(cs.ID, id) {
			rep.Add(format.Issue{Severity: format.Warning, Code: "sab_system_mismatch",
				Message: fmt.Sprintf("SAB %s usually belongs to %s, not %s", sab, cs.ID, id)})
		}
	}
	if id != "" && id != "umls" {
		if natives := format.NativeFormats(id); len(natives) > 0 {
			var names []string
			for _, n := range natives {
				names = append(names, n.Name)
			}
			rep.Add(format.Issue{Severity: format.Info, Code: "native_format_available",
				Message: fmt.Sprintf("%s also has a vendor format (%s), which carries more structure than UMLS rows", id, strings.Join(names, ", "))})
		}
	}
	return id, sab
}

func contains(xs []string, s string) bool {
	for _, x := range xs {
		if strings.EqualFold(x, s) {
			return true
		}
	}
	return false
}

var validityRe = regexp.MustCompile(`^[\[(](\d{4}-\d{2}-\d{2})?,(\d{4}-\d{2}-\d{2})?[\])]$`)

// reconcile fills the request fields from what was detected, and flags disagreements.
func reconcile(m *Manifest, req Request, rep *format.Report) {
	d := m.Detected
	pick := func(field, given, detected string) string {
		if given == "" {
			return detected
		}
		if detected != "" && given != detected {
			rep.Add(format.Issue{Severity: format.Warning, Code: "metadata_mismatch",
				Message: fmt.Sprintf("--%s is %q but the release says %q", field, given, detected)})
		}
		return given
	}
	m.Version = pick("version", req.Version, d.Version)
	m.ReleaseDate = pick("release-date", req.ReleaseDate, d.ReleaseDate)
	m.FHIRVersionURI = pick("fhir-version-uri", req.FHIRVersionURI, d.FHIRVersionURI)
	m.Validity = req.Validity

	if m.Version == "" {
		rep.Add(format.Issue{Severity: format.Error, Code: "missing_version", Message: "the version couldn't be detected; pass --version"})
	}
	if m.ReleaseDate != "" {
		if _, err := time.Parse("2006-01-02", m.ReleaseDate); err != nil {
			rep.Add(format.Issue{Severity: format.Error, Code: "bad_release_date", Message: fmt.Sprintf("release date %q is not YYYY-MM-DD", m.ReleaseDate)})
		}
	}
	if m.CodeSystemID == "" {
		rep.Add(format.Issue{Severity: format.Error, Code: "missing_code_system", Message: "the code system couldn't be determined; pass --system"})
		return
	}
	if d.CodeSystemID != "" && !strings.EqualFold(d.CodeSystemID, m.CodeSystemID) {
		rep.Add(format.Issue{Severity: format.Error, Code: "format_system_mismatch",
			Message: fmt.Sprintf("the release is %s but --system is %s", d.CodeSystemID, m.CodeSystemID)})
	}

	// Mirrors the code_system_version_validity trigger so the mistake shows up before
	// registration. The suggestion is never applied automatically: April updates and
	// mid-year corrections make the right range a billing decision.
	cs := format.LookupCodeSystem(m.CodeSystemID)
	if cs == nil {
		return
	}
	switch {
	case cs.DateOfService && m.Validity == "":
		msg := fmt.Sprintf("%s is versioned by date of service; pass --validity", cs.ID)
		if d.ValiditySuggestion != "" {
			msg += fmt.Sprintf(" (the release name suggests %q)", d.ValiditySuggestion)
		}
		rep.Add(format.Issue{Severity: format.Error, Code: "missing_validity", Message: msg})
	case !cs.DateOfService && m.Validity != "":
		rep.Add(format.Issue{Severity: format.Error, Code: "unexpected_validity",
			Message: fmt.Sprintf("%s isn't versioned by date of service; --validity must be empty", cs.ID)})
	case m.Validity != "":
		if err := checkValidity(m.Validity); err != nil {
			rep.Add(format.Issue{Severity: format.Error, Code: "bad_validity", Message: err.Error()})
		}
	}
}

func checkValidity(v string) error {
	g := validityRe.FindStringSubmatch(v)
	if g == nil {
		return fmt.Errorf("validity %q is not a date range like [2026-10-01,2027-10-01)", v)
	}
	var lo, hi time.Time
	var err error
	if g[1] != "" {
		if lo, err = time.Parse("2006-01-02", g[1]); err != nil {
			return fmt.Errorf("validity lower bound %q: %v", g[1], err)
		}
	}
	if g[2] != "" {
		if hi, err = time.Parse("2006-01-02", g[2]); err != nil {
			return fmt.Errorf("validity upper bound %q: %v", g[2], err)
		}
	}
	if g[1] != "" && g[2] != "" && !lo.Before(hi) {
		return fmt.Errorf("validity %q is empty", v)
	}
	return nil
}

// Inspection describes sources without reading whole files: candidate formats with the metadata
// their names carry, and for UMLS the source list from MRSAB.
type Inspection struct {
	Sources    []InspectedSource `json:"sources"`
	Candidates []Candidate       `json:"candidates"`
}

// InspectedSource lists a source's logical files.
type InspectedSource struct {
	Path  string   `json:"path"`
	Kind  string   `json:"kind"`
	Bytes int64    `json:"bytes"`
	Files []string `json:"files"`
}

// Candidate is a format that matches, with the files it would read.
type Candidate struct {
	Format   string          `json:"format"`
	Origin   string          `json:"origin"`
	Systems  []string        `json:"code_systems,omitempty"`
	Matched  map[string]int  `json:"matched_files"`
	Metadata format.Metadata `json:"metadata"`
}

// Inspect opens the sources and reports what they look like.
func Inspect(paths []string, formatName string, opts format.Options) (*Inspection, error) {
	var srcs []*source.Source
	defer func() {
		for _, s := range srcs {
			_ = s.Close()
		}
	}()
	out := &Inspection{}
	for i, p := range paths {
		s, err := source.Open(p, i)
		if err != nil {
			return nil, err
		}
		srcs = append(srcs, s)
		is := InspectedSource{Path: filepath.ToSlash(p), Kind: string(s.Kind), Bytes: s.Size}
		for _, f := range s.Files() {
			is.Files = append(is.Files, f.Name)
		}
		out.Sources = append(out.Sources, is)
	}
	var formats []*format.Format
	if formatName != "" {
		f := format.Lookup(formatName)
		if f == nil {
			return nil, fmt.Errorf("unknown format %q", formatName)
		}
		formats = []*format.Format{f}
	} else {
		for _, c := range format.Detect(srcs) {
			formats = append(formats, c.Format)
		}
	}
	for _, f := range formats {
		sel, _ := format.Match(f, srcs)
		c := Candidate{Format: f.Name, Origin: string(f.Origin), Systems: f.CodeSystems, Matched: map[string]int{},
			Metadata: format.Sniff(sel, opts)}
		for id, fs := range sel.Files {
			c.Matched[id] = len(fs)
		}
		out.Candidates = append(out.Candidates, c)
	}
	return out, nil
}
