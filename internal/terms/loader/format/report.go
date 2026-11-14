// SPDX-License-Identifier: GPL-3.0-or-later

package format

import "sort"

// Severity of an issue. Any Error makes the ingest fail.
type Severity string

const (
	Error   Severity = "error"
	Warning Severity = "warning"
	Info    Severity = "info"
)

// Issue is one finding about a release.
type Issue struct {
	Severity Severity `json:"severity"`
	Code     string   `json:"code"`
	File     string   `json:"file,omitempty"`
	Line     int64    `json:"line,omitempty"`
	Message  string   `json:"message"`
}

// HasErrors reports whether any issue is an error.
func HasErrors(is []Issue) bool {
	for _, i := range is {
		if i.Severity == Error {
			return true
		}
	}
	return false
}

// Suppressed counts issues beyond the per-(file, code) cap.
type Suppressed struct {
	Severity Severity `json:"severity"`
	Code     string   `json:"code"`
	File     string   `json:"file,omitempty"`
	Count    int64    `json:"count"`
}

// Report collects issues, keeping at most Max per (severity, file, code) so a systematically
// broken file doesn't produce millions of lines. Totals still count everything.
type Report struct {
	Max      int
	Issues   []Issue
	Errors   int64
	Warnings int64

	seen       map[key]int
	suppressed map[key]int64
}

type key struct {
	sev        Severity
	file, code string
}

// NewReport returns a report that keeps max issues per (severity, file, code); max <= 0 keeps all.
func NewReport(max int) *Report {
	return &Report{Max: max, seen: map[key]int{}, suppressed: map[key]int64{}}
}

// Add records an issue.
func (r *Report) Add(i Issue) {
	switch i.Severity {
	case Error:
		r.Errors++
	case Warning:
		r.Warnings++
	}
	k := key{i.Severity, i.File, i.Code}
	if r.Max > 0 && r.seen[k] >= r.Max {
		r.suppressed[k]++
		return
	}
	r.seen[k]++
	r.Issues = append(r.Issues, i)
}

// AddAll records several issues.
func (r *Report) AddAll(is []Issue) {
	for _, i := range is {
		r.Add(i)
	}
}

// Suppressed returns the counts of issues that were not kept, in a stable order.
func (r *Report) Suppressed() []Suppressed {
	out := make([]Suppressed, 0, len(r.suppressed))
	for k, n := range r.suppressed {
		out = append(out, Suppressed{Severity: k.sev, Code: k.code, File: k.file, Count: n})
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.File != b.File {
			return a.File < b.File
		}
		if a.Severity != b.Severity {
			return a.Severity < b.Severity
		}
		return a.Code < b.Code
	})
	return out
}
