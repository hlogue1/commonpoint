// SPDX-License-Identifier: GPL-3.0-or-later

package tabular

import (
	"errors"
	"io"
	"strings"
	"testing"
)

type row struct {
	line   int64
	fields []string
	err    string
}

func readAll(t *testing.T, in string, l Layout) ([]row, error) {
	t.Helper()
	rd, err := NewReader(strings.NewReader(in), l)
	if err != nil {
		return nil, err
	}
	var out []row
	for {
		rec, err := rd.Next()
		if err == io.EOF {
			return out, nil
		}
		var re *RowError
		if errors.As(err, &re) {
			out = append(out, row{line: re.Line, err: re.Code})
			continue
		}
		if err != nil {
			return out, err
		}
		out = append(out, row{line: rec.Line, fields: append([]string(nil), rec.Fields...)})
	}
}

func TestDelimitedExactHeader(t *testing.T) {
	l := Layout{Kind: Delimited, Sep: "\t", Header: true, ExactHeader: true, Columns: []string{"id", "active"}}
	rows, err := readAll(t, "id\tactive\r\n1\t1\r\n2\r\n3\t0\r\n", l)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 || rows[1].err != "field_count" || rows[1].line != 3 || rows[2].fields[1] != "0" {
		t.Fatalf("rows %+v", rows)
	}

	_, err = readAll(t, "id\tstatus\n", l)
	var he *HeaderError
	if !errors.As(err, &he) {
		t.Fatalf("want header error, got %v", err)
	}
}

func TestRequiredColumns(t *testing.T) {
	l := Layout{Kind: CSV, Header: true, Required: []string{"Code", "Grouping"}}
	_, err := readAll(t, "Code,Other\n", l)
	if err == nil || !strings.Contains(err.Error(), "Grouping") {
		t.Fatalf("want missing Grouping, got %v", err)
	}
	rd, err := NewReader(strings.NewReader("grouping,CODE,extra\n\"a, b\",\"x\"\"y\",z\n"), l)
	if err != nil {
		t.Fatal(err)
	}
	rec, err := rd.Next()
	if err != nil {
		t.Fatal(err)
	}
	if rec.Get("code") != `x"y` || rec.Get("Grouping") != "a, b" || rec.Line != 2 {
		t.Fatalf("got %q %q line %d", rec.Get("code"), rec.Get("Grouping"), rec.Line)
	}
}

func TestRRFTrailingSeparatorAndPadding(t *testing.T) {
	l := Layout{Kind: Delimited, Sep: "|", Columns: []string{"a", "b", "c"}}
	rows, err := readAll(t, "1|2|3|\n1|2|3\n1|\n\n", l)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 3 || rows[0].err != "" || rows[1].err != "" || rows[2].err != "field_count" {
		t.Fatalf("rows %+v", rows)
	}
	l.AllowFewer = true
	rows, _ = readAll(t, "1|2\n", l)
	if len(rows) != 1 || rows[0].err != "" || len(rows[0].fields) != 3 {
		t.Fatalf("padding: %+v", rows)
	}
}

func TestFixed(t *testing.T) {
	l := Layout{Kind: Fixed, MinLen: 10, Fields: []FixedField{
		{Name: "order", Start: 1, End: 5}, {Name: "code", Start: 7, End: 13}, {Name: "valid", Start: 15, End: 15},
		{Name: "long", Start: 17},
	}}
	in := "00001 A00     0 Short header\n00002 A000    1 Long name of thing\nshort\n"
	rd, err := NewReader(strings.NewReader(in), l)
	if err != nil {
		t.Fatal(err)
	}
	rec, _ := rd.Next()
	if rec.Get("code") != "A00" || rec.Get("valid") != "0" || rec.Get("long") != "Short header" {
		t.Fatalf("got %v", rec.Fields)
	}
	rec, _ = rd.Next()
	if rec.Get("order") != "00002" || rec.Get("code") != "A000" {
		t.Fatalf("got %v", rec.Fields)
	}
	if _, err := rd.Next(); err == nil || !strings.Contains(err.Error(), "at least 10") {
		t.Fatalf("want short line error, got %v", err)
	}
}

func TestInvalidUTF8Counted(t *testing.T) {
	rd, err := NewReader(strings.NewReader("a|\xff|\n"), Layout{Kind: Delimited, Sep: "|", Columns: []string{"x", "y"}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := rd.Next(); err != nil {
		t.Fatal(err)
	}
	if rd.InvalidUTF8Lines() != 1 {
		t.Fatalf("invalid = %d", rd.InvalidUTF8Lines())
	}
}
