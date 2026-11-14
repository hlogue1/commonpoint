// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"regexp"
	"strconv"
	"strings"
	"time"
)

// SCTID partition identifiers (the two digits before the check digit).
const (
	PartitionConcept      = "concept"
	PartitionDescription  = "description"
	PartitionRelationship = "relationship"
)

var verhoeffD = [10][10]int{
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
	{1, 2, 3, 4, 0, 6, 7, 8, 9, 5},
	{2, 3, 4, 0, 1, 7, 8, 9, 5, 6},
	{3, 4, 0, 1, 2, 8, 9, 5, 6, 7},
	{4, 0, 1, 2, 3, 9, 5, 6, 7, 8},
	{5, 9, 8, 7, 6, 0, 4, 3, 2, 1},
	{6, 5, 9, 8, 7, 1, 0, 4, 3, 2},
	{7, 6, 5, 9, 8, 2, 1, 0, 4, 3},
	{8, 7, 6, 5, 9, 3, 2, 1, 0, 4},
	{9, 8, 7, 6, 5, 4, 3, 2, 1, 0},
}

var verhoeffP = [8][10]int{
	{0, 1, 2, 3, 4, 5, 6, 7, 8, 9},
	{1, 5, 7, 6, 2, 8, 3, 0, 9, 4},
	{5, 8, 0, 3, 7, 9, 6, 1, 4, 2},
	{8, 9, 1, 6, 0, 4, 3, 5, 2, 7},
	{9, 4, 5, 3, 1, 2, 6, 8, 7, 0},
	{4, 2, 8, 6, 5, 7, 3, 9, 0, 1},
	{2, 7, 9, 3, 8, 0, 6, 4, 1, 5},
	{7, 0, 4, 2, 6, 5, 9, 3, 8, 1},
}

var verhoeffInv = [10]int{0, 4, 3, 2, 1, 5, 6, 7, 8, 9}

// VerhoeffValid reports whether the last digit of s is its Verhoeff check digit.
func VerhoeffValid(s string) bool {
	c := 0
	for i := 0; i < len(s); i++ {
		d := s[len(s)-1-i]
		if d < '0' || d > '9' {
			return false
		}
		c = verhoeffD[c][verhoeffP[i%8][d-'0']]
	}
	return c == 0
}

// VerhoeffDigit returns the check digit to append to s.
func VerhoeffDigit(s string) byte {
	c := 0
	for i := 0; i < len(s); i++ {
		d := s[len(s)-1-i]
		c = verhoeffD[c][verhoeffP[(i+1)%8][d-'0']]
	}
	return byte('0' + verhoeffInv[c])
}

// SCTIDKind returns the component type a valid SCTID identifies, or "" if s isn't one.
func SCTIDKind(s string) string {
	if len(s) < 6 || len(s) > 18 || s[0] == '0' || !VerhoeffValid(s) {
		return ""
	}
	switch s[len(s)-3 : len(s)-1] {
	case "00", "10":
		return PartitionConcept
	case "01", "11":
		return PartitionDescription
	case "02", "12":
		return PartitionRelationship
	}
	return ""
}

// IsSCTID reports whether s is a valid SCTID of any component type.
func IsSCTID(s string) bool { return SCTIDKind(s) != "" }

// LOINCValid checks a LOINC term code "NNNNN-C" with the LOINC mod-10 check digit (the Luhn
// algorithm over the digits). Answer (LA), answer list (LL), part (LP) and group (LG) codes
// get a pattern check only: their check digits aren't computed the same way.
func LOINCValid(s string) bool {
	if len(s) > 2 && s[0] == 'L' && strings.ContainsRune("APLG", rune(s[1])) {
		return loincPrefixed.MatchString(s)
	}
	i := strings.IndexByte(s, '-')
	if i < 1 || i != len(s)-2 || !isDigits(s[:i]) || !isDigits(s[i+1:]) {
		return false
	}
	return luhnDigit(s[:i]) == s[i+1]
}

var loincPrefixed = regexp.MustCompile(`^L[APLG]\d+-\d$`)

func luhnDigit(s string) byte {
	sum := 0
	double := true
	for i := len(s) - 1; i >= 0; i-- {
		d := int(s[i] - '0')
		if double {
			d *= 2
			if d > 9 {
				d -= 9
			}
		}
		sum += d
		double = !double
	}
	return byte('0' + (10-sum%10)%10)
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

// yyyymmdd parses an RF2-style date.
func yyyymmdd(s string) (time.Time, bool) {
	if len(s) != 8 {
		return time.Time{}, false
	}
	t, err := time.Parse("20060102", s)
	return t, err == nil
}

func isoDate(t time.Time) string { return t.Format("2006-01-02") }

var uuidRe = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

func atoi(s string) (int, bool) {
	n, err := strconv.Atoi(s)
	return n, err == nil
}

// sourceBases returns the base names of the sources (archive or directory names), which
// publishers use to carry the version.
func sourceBases(sel *Selection) []string {
	var out []string
	for _, s := range sel.Sources {
		p := strings.ReplaceAll(s.Path, "\\", "/")
		if i := strings.LastIndexByte(p, '/'); i >= 0 {
			p = p[i+1:]
		}
		out = append(out, p)
	}
	return out
}

// firstSubmatch returns the first match of re in the source bases, then in the file names.
func firstSubmatch(sel *Selection, re *regexp.Regexp) []string {
	for _, b := range sourceBases(sel) {
		if m := re.FindStringSubmatch(b); m != nil {
			return m
		}
	}
	for _, s := range sel.Sources {
		for _, f := range s.Files() {
			if m := re.FindStringSubmatch(f.Name); m != nil {
				return m
			}
		}
	}
	return nil
}

// fiscalYearValidity returns the US federal fiscal year range for ICD-10 FY y:
// [y-1-10-01, y-10-01).
func fiscalYearValidity(y int) string {
	return "[" + strconv.Itoa(y-1) + "-10-01," + strconv.Itoa(y) + "-10-01)"
}
