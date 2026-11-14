// SPDX-License-Identifier: GPL-3.0-or-later

package format

import (
	"os"
	"regexp"
	"strings"
	"testing"
)

func TestSCTID(t *testing.T) {
	// Well-known metadata ids.
	for id, kind := range map[string]string{
		SnomedIsA:                 PartitionConcept,
		SnomedFSNType:             PartitionConcept,
		SnomedInternationalModule: PartitionConcept,
		SnomedUSModule:            PartitionConcept,
		"404684003":               PartitionConcept,
		"900000000000011006":      PartitionConcept,
	} {
		if got := SCTIDKind(id); got != kind {
			t.Errorf("SCTIDKind(%s) = %q; want %q", id, got, kind)
		}
	}
	for _, bad := range []string{"116680004", "12345", "0116680003", "abc", ""} {
		if IsSCTID(bad) {
			t.Errorf("IsSCTID(%q) = true", bad)
		}
	}
	// Generated ids round-trip through the check digit and partition.
	for _, base := range []string{"100000", "1234567", "99999999"} {
		for part, kind := range map[string]string{"00": PartitionConcept, "01": PartitionDescription, "02": PartitionRelationship} {
			s := base + part
			s += string(VerhoeffDigit(s))
			if got := SCTIDKind(s); got != kind {
				t.Errorf("SCTIDKind(%s) = %q; want %q", s, got, kind)
			}
		}
	}
}

func TestLOINCCheckDigit(t *testing.T) {
	for _, ok := range []string{"2345-7", "718-7", "12345-5", "LA33-6", "LL360-9", "LP12345-1"} {
		if !LOINCValid(ok) {
			t.Errorf("LOINCValid(%q) = false", ok)
		}
	}
	for _, bad := range []string{"2345-6", "2345", "-7", "2345-77", "A345-7", "LA-6"} {
		if LOINCValid(bad) {
			t.Errorf("LOINCValid(%q) = true", bad)
		}
	}
}

// The catalog must mirror the code_system seed in 001_core.sql.
func TestCatalogMatchesSeed(t *testing.T) {
	b, err := os.ReadFile("../../../../migrations/terminology/001_core.sql")
	if err != nil {
		t.Fatal(err)
	}
	row := regexp.MustCompile(`(?m)^\s*\('([a-z0-9_]+)',\s*'([^']+)',.*,\s*(true|false)\)[,;]`)
	seed := map[string][2]string{}
	for _, m := range row.FindAllStringSubmatch(string(b), -1) {
		seed[m[1]] = [2]string{m[2], m[3]}
	}
	if len(seed) < 40 {
		t.Fatalf("parsed only %d seed rows; has the seed format changed?", len(seed))
	}
	for id, v := range seed {
		cs := LookupCodeSystem(id)
		if cs == nil {
			t.Errorf("catalog is missing %s", id)
			continue
		}
		if cs.URI != v[0] {
			t.Errorf("%s uri: catalog %s, seed %s", id, cs.URI, v[0])
		}
		if dos := v[1] == "true"; cs.DateOfService != dos {
			t.Errorf("%s date_of_service_versioned: catalog %v, seed %v", id, cs.DateOfService, dos)
		}
	}
	if len(Catalog) != len(seed) {
		t.Errorf("catalog has %d systems; seed has %d", len(Catalog), len(seed))
	}
}

func TestRegistryIsConsistent(t *testing.T) {
	seenSAB := map[string]string{}
	for _, cs := range Catalog {
		for _, s := range cs.SABs {
			if other, dup := seenSAB[s]; dup {
				t.Errorf("SAB %s maps to %s and %s", s, other, cs.ID)
			}
			seenSAB[s] = cs.ID
		}
	}
	for _, f := range All() {
		if !strings.HasPrefix(f.SourceFormat, "SOURCE_FORMAT_") {
			t.Errorf("%s: SourceFormat %q", f.Name, f.SourceFormat)
		}
		for _, cs := range f.CodeSystems {
			if LookupCodeSystem(cs) == nil {
				t.Errorf("%s produces unknown code system %s", f.Name, cs)
			}
		}
		ids := map[string]bool{}
		for _, s := range f.Files {
			if ids[s.ID] {
				t.Errorf("%s: duplicate spec %s", f.Name, s.ID)
			}
			ids[s.ID] = true
			if s.Layout.Kind == 0 {
				if _, ok := f.New(Options{}).(Streamer); !ok {
					t.Errorf("%s/%s has no layout and the checker isn't a Streamer", f.Name, s.ID)
				}
			}
		}
	}
}

func TestVersionLess(t *testing.T) {
	if !versionLess("2.9", "2.10") || versionLess("2.10", "2.9") || !versionLess("", "2.1") || versionLess("2.1", "2.1") {
		t.Fatal("versionLess")
	}
}
