// SPDX-License-Identifier: GPL-3.0-or-later

// Package source opens terminology release sources, which can be a zip archive, a directory,
// or a single file, as a sorted list of logical files, and computes each source's SHA-256 identity.
//
// A logical file hides two packaging details that publishers use:
//   - gzip compression (`MRCONSO.RRF.gz`), and
//   - split parts (`MRCONSO.RRF.aa`, `MRCONSO.RRF.ab`, … in the original UMLS distribution),
//     which are concatenated in name order.
package source

import (
	"archive/zip"
	"compress/gzip"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// Kind is how a source is packaged.
type Kind string

const (
	KindZip  Kind = "zip"
	KindDir  Kind = "dir"
	KindFile Kind = "file"
)

// Source is one release source given to ingest (e.g. the International and US SNOMED
// packages are two sources of one version).
type Source struct {
	Index int
	Path  string // cleaned path as given
	// Label names the source in messages; it defaults to Path. Ingest sets it to the
	// path relative to the ingest directory so reports don't depend on the local machine.
	Label string
	Kind  Kind
	Size  int64 // bytes on disk (sum of files for a directory)

	files []*File
	zr    *zip.ReadCloser
}

// File is a logical file inside a source.
type File struct {
	Source *Source
	Name   string // slash-separated path inside the source, without .gz / split suffix
	Size   int64  // stored bytes of all parts (compressed size for .gz)
	parts  []part
}

type part struct {
	name string
	open func() (io.ReadCloser, error)
	size int64
}

// Base returns the last element of the logical name.
func (f *File) Base() string { return path.Base(f.Name) }

// Parts returns the stored names that make up this logical file.
func (f *File) Parts() []string {
	out := make([]string, len(f.parts))
	for i, p := range f.parts {
		out[i] = p.name
	}
	return out
}

// String identifies the file for messages: "<source>!<name>".
func (f *File) String() string { return f.Source.label() + "!" + f.Name }

func (s *Source) label() string {
	if s.Label != "" {
		return s.Label
	}
	return filepath.ToSlash(s.Path)
}

// Open returns the decompressed, concatenated content of the logical file.
func (f *File) Open() (io.ReadCloser, error) {
	readers := make([]io.Reader, 0, len(f.parts))
	closers := make([]io.Closer, 0, len(f.parts)*2)
	closeAll := func() {
		for _, c := range closers {
			_ = c.Close()
		}
	}
	for _, p := range f.parts {
		rc, err := p.open()
		if err != nil {
			closeAll()
			return nil, fmt.Errorf("open %s: %w", p.name, err)
		}
		closers = append(closers, rc)
		var r io.Reader = rc
		if strings.HasSuffix(strings.ToLower(p.name), ".gz") {
			gz, err := gzip.NewReader(rc)
			if err != nil {
				closeAll()
				return nil, fmt.Errorf("gunzip %s: %w", p.name, err)
			}
			closers = append(closers, gz)
			r = gz
		}
		readers = append(readers, r)
	}
	return &multiCloser{Reader: io.MultiReader(readers...), close: closeAll}, nil
}

type multiCloser struct {
	io.Reader
	close func()
}

func (m *multiCloser) Close() error { m.close(); return nil }

// Open opens a source at p. index is its position in the ingest request.
func Open(p string, index int) (*Source, error) {
	p = filepath.Clean(p)
	st, err := os.Stat(p)
	if err != nil {
		return nil, err
	}
	s := &Source{Index: index, Path: p}
	var raw []part
	switch {
	case st.IsDir():
		s.Kind = KindDir
		err = filepath.WalkDir(p, func(fp string, d fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !d.Type().IsRegular() {
				return nil
			}
			rel, err := filepath.Rel(p, fp)
			if err != nil {
				return err
			}
			info, err := d.Info()
			if err != nil {
				return err
			}
			s.Size += info.Size()
			raw = append(raw, part{name: filepath.ToSlash(rel), size: info.Size(), open: osOpener(fp)})
			return nil
		})
		if err != nil {
			return nil, err
		}
	case strings.EqualFold(filepath.Ext(p), ".zip"):
		s.Kind = KindZip
		s.Size = st.Size()
		zr, err := zip.OpenReader(p)
		if err != nil {
			return nil, fmt.Errorf("open zip %s: %w", p, err)
		}
		s.zr = zr
		for _, zf := range zr.File {
			if zf.FileInfo().IsDir() {
				continue
			}
			zf := zf
			raw = append(raw, part{name: zf.Name, size: int64(zf.CompressedSize64), open: zf.Open})
		}
	default:
		s.Kind = KindFile
		s.Size = st.Size()
		raw = append(raw, part{name: filepath.Base(p), size: st.Size(), open: osOpener(p)})
	}
	s.files = group(s, raw)
	return s, nil
}

func osOpener(p string) func() (io.ReadCloser, error) {
	return func() (io.ReadCloser, error) { return os.Open(p) }
}

// splitSuffix matches a split part suffix after a known data extension: MRCONSO.RRF.aa
var splitSuffix = regexp.MustCompile(`(?i)(\.(?:rrf|txt|csv|asc))\.([a-z]{2})$`)

// LogicalName strips .gz and a split part suffix from a stored name.
func LogicalName(name string) string {
	n := name
	if strings.HasSuffix(strings.ToLower(n), ".gz") {
		n = n[:len(n)-3]
	}
	return splitSuffix.ReplaceAllString(n, "$1")
}

func group(s *Source, raw []part) []*File {
	sort.Slice(raw, func(i, j int) bool { return raw[i].name < raw[j].name })
	byName := map[string]*File{}
	var out []*File
	for _, p := range raw {
		ln := LogicalName(p.name)
		f, ok := byName[ln]
		if !ok {
			f = &File{Source: s, Name: ln}
			byName[ln] = f
			out = append(out, f)
		}
		f.parts = append(f.parts, p)
		f.Size += p.size
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Name < out[j].Name })
	return out
}

// Files returns the logical files of the source, sorted by name.
func (s *Source) Files() []*File { return s.files }

// Close releases the archive handle, if any.
func (s *Source) Close() error {
	if s.zr != nil {
		return s.zr.Close()
	}
	return nil
}

// SHA256 is the source's identity (ROADMAP D6a):
//   - zip or single file: SHA-256 of the file's bytes, so it matches the publisher's
//     checksum and `shasum -a 256`;
//   - directory: SHA-256 of a `sha256sum`-style listing ("<hex>  <relative/path>\n"
//     for every regular file, sorted by path), so the same tree hashes the same anywhere.
func (s *Source) SHA256() (string, error) {
	switch s.Kind {
	case KindDir:
		h := sha256.New()
		var names []string
		opens := map[string]func() (io.ReadCloser, error){}
		for _, f := range s.files {
			for _, p := range f.parts {
				names = append(names, p.name)
				opens[p.name] = p.open
			}
		}
		sort.Strings(names)
		for _, n := range names {
			sum, err := hashOpen(opens[n])
			if err != nil {
				return "", fmt.Errorf("hash %s: %w", n, err)
			}
			fmt.Fprintf(h, "%s  %s\n", sum, n)
		}
		return hex.EncodeToString(h.Sum(nil)), nil
	default:
		return hashOpen(osOpener(s.Path))
	}
}

func hashOpen(open func() (io.ReadCloser, error)) (string, error) {
	rc, err := open()
	if err != nil {
		return "", err
	}
	defer rc.Close()
	h := sha256.New()
	if _, err := io.Copy(h, rc); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}
