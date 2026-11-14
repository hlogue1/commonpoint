// SPDX-License-Identifier: GPL-3.0-or-later

package source

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, p string, b []byte) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, b, 0o644); err != nil {
		t.Fatal(err)
	}
}

func gz(t *testing.T, s string) []byte {
	var b bytes.Buffer
	w := gzip.NewWriter(&b)
	_, _ = w.Write([]byte(s))
	if err := w.Close(); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func readAll(t *testing.T, f *File) string {
	t.Helper()
	rc, err := f.Open()
	if err != nil {
		t.Fatal(err)
	}
	defer rc.Close()
	b, err := io.ReadAll(rc)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func TestDirGroupsSplitAndGzipParts(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "META", "MRCONSO.RRF.aa.gz"), gz(t, "a|\n"))
	write(t, filepath.Join(dir, "META", "MRCONSO.RRF.ab.gz"), gz(t, "b|\n"))
	write(t, filepath.Join(dir, "META", "MRSAB.RRF"), []byte("x|\n"))

	s, err := Open(dir, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if s.Kind != KindDir {
		t.Fatalf("kind %s", s.Kind)
	}
	fs := s.Files()
	if len(fs) != 2 || fs[0].Name != "META/MRCONSO.RRF" || fs[1].Name != "META/MRSAB.RRF" {
		t.Fatalf("files %v", names(fs))
	}
	if got := readAll(t, fs[0]); got != "a|\nb|\n" {
		t.Fatalf("concatenated parts = %q", got)
	}
	if len(fs[0].Parts()) != 2 {
		t.Fatalf("parts %v", fs[0].Parts())
	}
}

func names(fs []*File) []string {
	var out []string
	for _, f := range fs {
		out = append(out, f.Name)
	}
	return out
}

func TestZipAndChecksums(t *testing.T) {
	dir := t.TempDir()
	zp := filepath.Join(dir, "release.zip")
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	w, _ := zw.Create("Release/Snapshot/a.txt")
	_, _ = w.Write([]byte("hello\n"))
	_, _ = zw.Create("Release/empty-dir/")
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	write(t, zp, buf.Bytes())

	s, err := Open(zp, 3)
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if s.Kind != KindZip || s.Index != 3 {
		t.Fatalf("kind %s index %d", s.Kind, s.Index)
	}
	if fs := s.Files(); len(fs) != 1 || readAll(t, fs[0]) != "hello\n" {
		t.Fatalf("files %v", names(s.Files()))
	}
	sum, err := s.SHA256()
	if err != nil {
		t.Fatal(err)
	}
	want := sha256.Sum256(buf.Bytes())
	if sum != hex.EncodeToString(want[:]) {
		t.Fatalf("zip sha256 should be the file's sha256")
	}
}

func TestDirChecksumIsStable(t *testing.T) {
	mk := func() string {
		dir := t.TempDir()
		write(t, filepath.Join(dir, "b.txt"), []byte("2"))
		write(t, filepath.Join(dir, "a", "c.txt"), []byte("1"))
		s, err := Open(dir, 0)
		if err != nil {
			t.Fatal(err)
		}
		sum, err := s.SHA256()
		if err != nil {
			t.Fatal(err)
		}
		return sum
	}
	a, b := mk(), mk()
	if a != b {
		t.Fatalf("same tree, different sums: %s %s", a, b)
	}
	// sha256sum-style listing, sorted by path.
	h1 := sha256.Sum256([]byte("1"))
	h2 := sha256.Sum256([]byte("2"))
	listing := hex.EncodeToString(h1[:]) + "  a/c.txt\n" + hex.EncodeToString(h2[:]) + "  b.txt\n"
	want := sha256.Sum256([]byte(listing))
	if a != hex.EncodeToString(want[:]) {
		t.Fatalf("dir sum %s isn't the hash of the sorted listing", a)
	}
}

func TestDecode(t *testing.T) {
	for _, tc := range []struct {
		name string
		in   []byte
		enc  Encoding
	}{
		{"plain", []byte("Code|é\n"), UTF8},
		{"utf8 bom", append([]byte{0xEF, 0xBB, 0xBF}, "Code|é\n"...), UTF8BOM},
		{"utf16le", []byte{0xFF, 0xFE, 'C', 0, 'o', 0, 'd', 0, 'e', 0, '|', 0, 0xE9, 0, '\n', 0}, UTF16LE},
		{"utf16be", []byte{0xFE, 0xFF, 0, 'C', 0, 'o', 0, 'd', 0, 'e', 0, '|', 0, 0xE9, 0, '\n'}, UTF16BE},
	} {
		t.Run(tc.name, func(t *testing.T) {
			r, enc := Decode(bytes.NewReader(tc.in))
			b, _ := io.ReadAll(r)
			if enc != tc.enc || string(b) != "Code|é\n" {
				t.Fatalf("got %q (%s)", b, enc)
			}
		})
	}
}

func TestLogicalName(t *testing.T) {
	for in, want := range map[string]string{
		"META/MRCONSO.RRF.aa.gz": "META/MRCONSO.RRF",
		"META/MRCONSO.RRF.ab":    "META/MRCONSO.RRF",
		"x/Loinc.csv":            "x/Loinc.csv",
		"x/notes.aa":             "x/notes.aa",
		"llt.asc.gz":             "llt.asc",
	} {
		if got := LogicalName(in); got != want {
			t.Errorf("LogicalName(%q) = %q; want %q", in, got, want)
		}
	}
}
