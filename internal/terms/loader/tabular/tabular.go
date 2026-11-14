// SPDX-License-Identifier: GPL-3.0-or-later

// Package tabular reads the row-oriented layouts that terminology publishers ship:
// tab-delimited with a header (SNOMED RF2), RFC 4180 CSV (LOINC, NUCC), delimited without a
// header and with a trailing separator (UMLS/RxNorm RRF with `|`, MedDRA ASCII with `$`), and
// fixed-width (CMS ICD-10 order files, HCPCS).
//
// Malformed rows come back as *RowError and reading continues, so one bad row does not hide
// the rest of a file's problems.
package tabular

import (
	"bufio"
	"encoding/csv"
	"errors"
	"fmt"
	"io"
	"strings"
	"unicode/utf8"
)

// Kind selects the parser.
type Kind int

const (
	// Delimited splits each line on Sep with no quoting (RF2, RRF, MedDRA ASCII).
	Delimited Kind = iota + 1
	// CSV is RFC 4180 with quoting and embedded newlines.
	CSV
	// Fixed slices each line into fixed column ranges.
	Fixed
)

// Layout describes one file's physical layout.
type Layout struct {
	Kind Kind
	Sep  string // Delimited only

	// Header: the first row names the columns.
	Header bool
	// ExactHeader: the header must equal Columns, in order (RF2).
	ExactHeader bool
	// Columns: for headerless files, the column names by position; with ExactHeader, the
	// expected header.
	Columns []string
	// Required: columns that must appear in a header (case-insensitive, any order).
	Required []string
	// AllowFewer pads rows with fewer fields than Columns instead of rejecting them, for
	// publishers that drop empty trailing fields.
	AllowFewer bool

	Fields []FixedField // Fixed only
	// MinLen is the shortest acceptable fixed-width line, in runes.
	MinLen int
}

// FixedField is a 1-based, inclusive column range. End 0 means to the end of the line.
type FixedField struct {
	Name       string
	Start, End int
}

// Record is one data row. Fields are owned by the caller only until the next Next call.
type Record struct {
	Line   int64 // physical line where the row starts (1-based)
	Fields []string
	cols   map[string]int
}

// Get returns the named field ("" if the column is absent). Names are case-insensitive.
func (r Record) Get(name string) string {
	i, ok := r.cols[strings.ToLower(name)]
	if !ok || i >= len(r.Fields) {
		return ""
	}
	return r.Fields[i]
}

// Has reports whether the file has the named column.
func (r Record) Has(name string) bool {
	_, ok := r.cols[strings.ToLower(name)]
	return ok
}

// RowError is a malformed row. The reader stays usable.
type RowError struct {
	Line int64
	Code string
	Msg  string
}

func (e *RowError) Error() string { return fmt.Sprintf("line %d: %s", e.Line, e.Msg) }

// HeaderError means the file can't be read with this layout at all.
type HeaderError struct{ Msg string }

func (e *HeaderError) Error() string { return e.Msg }

// Reader yields records from one file.
type Reader struct {
	l       Layout
	cols    []string
	idx     map[string]int
	scan    *bufio.Scanner
	csv     *csv.Reader
	line    int64
	invalid int64 // lines with invalid UTF-8
	fields  []string
}

// MaxLine bounds one physical line. UMLS MRSAT and MRDEF have very long values.
const MaxLine = 64 << 20

// NewReader prepares a reader and, for headered layouts, reads and checks the header.
func NewReader(r io.Reader, l Layout) (*Reader, error) {
	rd := &Reader{l: l}
	switch l.Kind {
	case CSV:
		rd.csv = csv.NewReader(r)
		rd.csv.FieldsPerRecord = -1
		rd.csv.ReuseRecord = true
	case Delimited, Fixed:
		rd.scan = bufio.NewScanner(r)
		rd.scan.Buffer(make([]byte, 0, 1<<20), MaxLine)
	default:
		return nil, &HeaderError{Msg: "unknown layout kind"}
	}
	if l.Kind == Fixed {
		for _, f := range l.Fields {
			rd.cols = append(rd.cols, f.Name)
		}
		rd.index()
		return rd, nil
	}
	if !l.Header {
		rd.cols = l.Columns
		rd.index()
		return rd, nil
	}
	hdr, err := rd.rawNext()
	if err == io.EOF {
		return nil, &HeaderError{Msg: "file is empty; expected a header row"}
	}
	if err != nil {
		return nil, &HeaderError{Msg: "reading header: " + err.Error()}
	}
	rd.cols = make([]string, len(hdr))
	for i, h := range hdr {
		rd.cols[i] = strings.TrimSpace(h)
	}
	rd.index()
	if l.ExactHeader {
		if !equalFold(rd.cols, l.Columns) {
			return nil, &HeaderError{Msg: fmt.Sprintf("header is [%s]; expected [%s]",
				strings.Join(rd.cols, " "), strings.Join(l.Columns, " "))}
		}
	}
	var missing []string
	for _, c := range l.Required {
		if _, ok := rd.idx[strings.ToLower(c)]; !ok {
			missing = append(missing, c)
		}
	}
	if len(missing) > 0 {
		return nil, &HeaderError{Msg: "header is missing required columns: " + strings.Join(missing, ", ")}
	}
	return rd, nil
}

func (rd *Reader) index() {
	rd.idx = make(map[string]int, len(rd.cols))
	for i, c := range rd.cols {
		k := strings.ToLower(c)
		if _, dup := rd.idx[k]; !dup {
			rd.idx[k] = i
		}
	}
}

func equalFold(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !strings.EqualFold(a[i], b[i]) {
			return false
		}
	}
	return true
}

// Columns returns the column names in file order.
func (rd *Reader) Columns() []string { return rd.cols }

// InvalidUTF8Lines counts lines that were not valid UTF-8.
func (rd *Reader) InvalidUTF8Lines() int64 { return rd.invalid }

// Line returns the last physical line read.
func (rd *Reader) Line() int64 { return rd.line }

// rawNext returns the fields of the next physical row.
func (rd *Reader) rawNext() ([]string, error) {
	if rd.csv != nil {
		rec, err := rd.csv.Read()
		if err != nil {
			var pe *csv.ParseError
			if errors.As(err, &pe) {
				rd.line = int64(pe.StartLine)
				return nil, &RowError{Line: int64(pe.StartLine), Code: "csv_syntax", Msg: pe.Err.Error()}
			}
			return nil, err
		}
		line, _ := rd.csv.FieldPos(0)
		rd.line = int64(line)
		for _, f := range rec {
			if !utf8.ValidString(f) {
				rd.invalid++
				break
			}
		}
		return rec, nil
	}
	if !rd.scan.Scan() {
		if err := rd.scan.Err(); err != nil {
			if errors.Is(err, bufio.ErrTooLong) {
				return nil, &HeaderError{Msg: fmt.Sprintf("line %d is longer than %d bytes", rd.line+1, MaxLine)}
			}
			return nil, err
		}
		return nil, io.EOF
	}
	rd.line++
	s := strings.TrimSuffix(rd.scan.Text(), "\r")
	if !utf8.ValidString(s) {
		rd.invalid++
	}
	if rd.l.Kind == Fixed {
		return []string{s}, nil
	}
	rd.fields = rd.fields[:0]
	for {
		i := strings.Index(s, rd.l.Sep)
		if i < 0 {
			rd.fields = append(rd.fields, s)
			break
		}
		rd.fields = append(rd.fields, s[:i])
		s = s[i+len(rd.l.Sep):]
	}
	return rd.fields, nil
}

// Next returns the next data row, io.EOF at the end, a *RowError for a malformed row
// (call Next again to continue), or another error if the file can't be read further.
func (rd *Reader) Next() (Record, error) {
	for {
		f, err := rd.rawNext()
		if err != nil {
			return Record{}, err
		}
		if rd.l.Kind == Fixed {
			return rd.fixed(f[0])
		}
		if len(f) == 1 && f[0] == "" && rd.csv == nil {
			continue // blank line
		}
		n := len(rd.cols)
		// RRF and MedDRA end every row with the separator; tolerate it everywhere.
		if len(f) == n+1 && f[n] == "" {
			f = f[:n]
		}
		if len(f) < n && rd.l.AllowFewer {
			for len(f) < n {
				f = append(f, "")
			}
		}
		if len(f) != n {
			return Record{}, &RowError{Line: rd.line, Code: "field_count",
				Msg: fmt.Sprintf("%d fields; expected %d", len(f), n)}
		}
		return Record{Line: rd.line, Fields: f, cols: rd.idx}, nil
	}
}

func (rd *Reader) fixed(line string) (Record, error) {
	if strings.TrimSpace(line) == "" {
		return rd.Next()
	}
	runes := []rune(line)
	if len(runes) < rd.l.MinLen {
		return Record{}, &RowError{Line: rd.line, Code: "short_line",
			Msg: fmt.Sprintf("line is %d characters; expected at least %d", len(runes), rd.l.MinLen)}
	}
	rd.fields = rd.fields[:0]
	for _, ff := range rd.l.Fields {
		start, end := ff.Start-1, ff.End
		if end == 0 || end > len(runes) {
			end = len(runes)
		}
		v := ""
		if start < len(runes) && start < end {
			v = strings.TrimSpace(string(runes[start:end]))
		}
		rd.fields = append(rd.fields, v)
	}
	return Record{Line: rd.line, Fields: rd.fields, cols: rd.idx}, nil
}
