// SPDX-License-Identifier: GPL-3.0-or-later

package source

import (
	"bufio"
	"io"

	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/transform"
)

// Encoding is the text encoding detected from a byte order mark.
type Encoding string

const (
	UTF8    Encoding = "utf-8"
	UTF8BOM Encoding = "utf-8-bom"
	UTF16LE Encoding = "utf-16le"
	UTF16BE Encoding = "utf-16be"
)

// Decode sniffs a byte order mark and returns a UTF-8 reader without it. Files with no BOM
// are passed through as UTF-8; invalid sequences are reported by the tabular reader.
// Some publishers ship UTF-16 text files (with a BOM); those are transcoded.
func Decode(r io.Reader) (io.Reader, Encoding) {
	br := bufio.NewReaderSize(r, 64*1024)
	b, _ := br.Peek(3)
	switch {
	case len(b) >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF:
		_, _ = br.Discard(3)
		return br, UTF8BOM
	case len(b) >= 2 && b[0] == 0xFF && b[1] == 0xFE:
		dec := unicode.UTF16(unicode.LittleEndian, unicode.ExpectBOM).NewDecoder()
		return transform.NewReader(br, dec), UTF16LE
	case len(b) >= 2 && b[0] == 0xFE && b[1] == 0xFF:
		dec := unicode.UTF16(unicode.BigEndian, unicode.ExpectBOM).NewDecoder()
		return transform.NewReader(br, dec), UTF16BE
	}
	return br, UTF8
}
