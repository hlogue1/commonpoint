// SPDX-License-Identifier: GPL-3.0-or-later

package ingest

// Every release here is synthetic: invented codes and descriptions, SCTIDs generated with valid
// Verhoeff check digits, and only well-known SNOMED metadata ids used as-is.

import (
	"archive/zip"
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	"github.com/hlogue1/commonpoint/internal/terms/loader/format"
)

type files map[string]string

func mkdir(t *testing.T, root string, fs files) string {
	t.Helper()
	for name, body := range fs {
		p := filepath.Join(root, filepath.FromSlash(name))
		if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return root
}

func mkzip(t *testing.T, path string, fs files) string {
	t.Helper()
	var buf bytes.Buffer
	zw := zip.NewWriter(&buf)
	var names []string
	for n := range fs {
		names = append(names, n)
	}
	for _, n := range sortStrings(names) {
		w, err := zw.Create(n)
		if err != nil {
			t.Fatal(err)
		}
		_, _ = w.Write([]byte(fs[n]))
	}
	if err := zw.Close(); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func sortStrings(s []string) []string {
	for i := range s {
		for j := i + 1; j < len(s); j++ {
			if s[j] < s[i] {
				s[i], s[j] = s[j], s[i]
			}
		}
	}
	return s
}

func run(t *testing.T, req Request) *Manifest {
	t.Helper()
	m, err := Run(context.Background(), req)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func codes(m *Manifest, sev format.Severity) map[string]int {
	out := map[string]int{}
	for _, i := range m.Issues {
		if i.Severity == sev {
			out[i.Code]++
		}
	}
	return out
}

func requireOK(t *testing.T, m *Manifest) {
	t.Helper()
	if !m.OK {
		b, _ := json.MarshalIndent(m, "", "  ")
		t.Fatalf("ingest failed:\n%s", b)
	}
}

func count(m *Manifest, name string) int64 {
	for _, c := range m.Detected.Counts {
		if c.Name == name {
			return c.Value
		}
	}
	return -1
}

// ---- SNOMED CT RF2 ----

func sctid(n int, partition string) string {
	s := strconv.Itoa(n) + partition
	return s + string(format.VerhoeffDigit(s))
}

const (
	intModule = format.SnomedInternationalModule
	usModule  = format.SnomedUSModule
	primitive = "900000000000074008"
	existent  = "900000000000451002"
	preferred = "900000000000548007"
	usLang    = "900000000000509007"
	caseInsen = "900000000000448009"
)

var (
	rootID  = sctid(100001, "00")
	childID = sctid(100002, "00")
	usID    = sctid(100003, "00")
)

func rf2(header string, rows ...string) string {
	return header + "\r\n" + strings.Join(rows, "\r\n") + "\r\n"
}

const (
	hConcept = "id\teffectiveTime\tactive\tmoduleId\tdefinitionStatusId"
	hDesc    = "id\teffectiveTime\tactive\tmoduleId\tconceptId\tlanguageCode\ttypeId\tterm\tcaseSignificanceId"
	hRel     = "id\teffectiveTime\tactive\tmoduleId\tsourceId\tdestinationId\trelationshipGroup\ttypeId\tcharacteristicTypeId\tmodifierId"
	hLang    = "id\teffectiveTime\tactive\tmoduleId\trefsetId\treferencedComponentId\tacceptabilityId"
)

func concept(id, date, module string) string {
	return strings.Join([]string{id, date, "1", module, primitive}, "\t")
}

func desc(n int, date, module, conceptID, typ, term string) string {
	return strings.Join([]string{sctid(n, "01"), date, "1", module, conceptID, "en", typ, term, caseInsen}, "\t")
}

func isa(n int, date, module, src, dst string) string {
	return strings.Join([]string{sctid(n, "02"), date, "1", module, src, dst, "0", format.SnomedIsA, format.SnomedInferred, existent}, "\t")
}

func lang(uuid, date, module, descID string) string {
	return strings.Join([]string{uuid, date, "1", module, usLang, descID, preferred}, "\t")
}

func snomedInt(t *testing.T, dir string, extraDesc ...string) string {
	d := "20260101"
	p := "SnomedCT_Fixture_INT_" + d + "/Snapshot/"
	descs := append([]string{
		desc(200001, d, intModule, rootID, format.SnomedFSNType, "Fixture root (fixture)"),
		desc(200002, d, intModule, childID, format.SnomedFSNType, "Fixture child (fixture)"),
		desc(200003, d, intModule, format.SnomedIsA, format.SnomedFSNType, "Fixture is a (attribute)"),
	}, extraDesc...)
	return mkzip(t, filepath.Join(dir, "SnomedCT_Fixture_INT_"+d+".zip"), files{
		p + "Terminology/sct2_Concept_Snapshot_INT_" + d + ".txt": rf2(hConcept,
			concept(rootID, d, intModule), concept(childID, d, intModule), concept(format.SnomedIsA, d, intModule)),
		p + "Terminology/sct2_Description_Snapshot-en_INT_" + d + ".txt": rf2(hDesc, descs...),
		p + "Terminology/sct2_Relationship_Snapshot_INT_" + d + ".txt": rf2(hRel,
			isa(300001, d, intModule, childID, rootID), isa(300002, d, intModule, format.SnomedIsA, rootID)),
		p + "Refset/Language/der2_cRefset_LanguageSnapshot-en_INT_" + d + ".txt": rf2(hLang,
			lang("00000000-0000-4000-8000-000000000001", d, intModule, sctid(200001, "01"))),
		p + "Terminology/sct2_StatedRelationship_Snapshot_INT_" + d + ".txt":                  "ignored",
		"SnomedCT_Fixture_INT_" + d + "/Full/Terminology/sct2_Concept_Full_INT_" + d + ".txt": "ignored",
	})
}

func snomedUS(t *testing.T, dir string) string {
	d := "20260301"
	p := "SnomedCT_Fixture_US1000124_" + d + "/Snapshot/"
	return mkzip(t, filepath.Join(dir, "SnomedCT_Fixture_US1000124_"+d+".zip"), files{
		p + "Terminology/sct2_Concept_Snapshot_US1000124_" + d + ".txt": rf2(hConcept, concept(usID, d, usModule)),
		p + "Terminology/sct2_Description_Snapshot-en_US1000124_" + d + ".txt": rf2(hDesc,
			desc(200004, d, usModule, usID, format.SnomedFSNType, "Fixture US concept (fixture)"),
			// Synonym on an International concept: the reference crosses packages.
			desc(200005, d, usModule, childID, "900000000000013009", "Fixture child synonym")),
		p + "Terminology/sct2_Relationship_Snapshot_US1000124_" + d + ".txt": rf2(hRel, isa(300003, d, usModule, usID, childID)),
		p + "Refset/Language/der2_cRefset_LanguageSnapshot-en_US1000124_" + d + ".txt": rf2(hLang,
			lang("00000000-0000-4000-8000-000000000002", d, usModule, sctid(200004, "01"))),
	})
}

func TestSnomedLayeredEditions(t *testing.T) {
	dir := t.TempDir()
	m := run(t, Request{Sources: []string{snomedInt(t, dir), snomedUS(t, dir)}, IngestDir: dir})
	requireOK(t, m)
	if m.Format != "snomed-rf2" || m.CodeSystemID != "snomed" || m.SourceFormat != "SOURCE_FORMAT_SNOMED_RF2_SNAPSHOT" {
		t.Fatalf("format %s system %s", m.Format, m.CodeSystemID)
	}
	if m.Version != "20260301" || m.ReleaseDate != "2026-03-01" {
		t.Fatalf("version %s release %s", m.Version, m.ReleaseDate)
	}
	if want := "http://snomed.info/sct/" + usModule + "/version/20260301"; m.FHIRVersionURI != want {
		t.Fatalf("fhir uri %s", m.FHIRVersionURI)
	}
	if len(m.Detected.Packages) != 2 || m.Detected.Packages[0] != "US1000124 20260301" {
		t.Fatalf("packages %v", m.Detected.Packages)
	}
	if m.Sources[0].Path != "SnomedCT_Fixture_INT_20260101.zip" {
		t.Fatalf("source path not relative to ingest dir: %s", m.Sources[0].Path)
	}
	bad := run(t, Request{Sources: []string{snomedInt(t, dir, desc(200010, "20260101", intModule, sctid(999999, "00"), format.SnomedFSNType, "x"))}, IngestDir: dir})
	if f := bad.Issues[0].File; !strings.HasPrefix(f, "SnomedCT_Fixture_INT_20260101.zip!") {
		t.Fatalf("issue file %q should be relative to the ingest dir", f)
	}
	if c := count(m, "concepts"); c != 4 {
		t.Fatalf("concepts = %d", c)
	}
	if c := count(m, "active inferred is-a relationships"); c != 3 {
		t.Fatalf("is-a = %d", c)
	}
	if len(m.Ignored) != 2 {
		t.Fatalf("ignored %v", m.Ignored)
	}
	for _, f := range m.Files {
		if len(f.SHA256) != 64 || f.Rows == 0 {
			t.Fatalf("file %+v", f)
		}
	}
}

func TestSnomedReportsBadRows(t *testing.T) {
	dir := t.TempDir()
	badCheck := rootID[:len(rootID)-1] + string("0123456789"[(int(rootID[len(rootID)-1]-'0')+1)%10])
	src := snomedInt(t, dir,
		desc(200010, "20260101", intModule, sctid(999999, "00"), format.SnomedFSNType, "Points nowhere"),
		desc(200011, "20260101", intModule, badCheck, format.SnomedFSNType, "Bad check digit"),
		strings.Join([]string{sctid(200012, "01"), "2026-01-01", "1", intModule, rootID, "en", format.SnomedFSNType, "Bad date", caseInsen}, "\t"),
	)
	m := run(t, Request{Sources: []string{src}})
	if m.OK {
		t.Fatal("expected failure")
	}
	got := codes(m, format.Error)
	for _, c := range []string{"unknown_concept", "bad_sctid", "bad_effective_time"} {
		if got[c] == 0 {
			t.Errorf("missing %s in %v", c, got)
		}
	}
}

func TestSnomedMissingRequiredFile(t *testing.T) {
	dir := t.TempDir()
	src := mkdir(t, filepath.Join(dir, "rel"), files{
		"Snapshot/Terminology/sct2_Concept_Snapshot_INT_20260101.txt": rf2(hConcept, concept(rootID, "20260101", intModule)),
	})
	m := run(t, Request{Sources: []string{src}, Format: "snomed-rf2"})
	if m.OK || codes(m, format.Error)["missing_file"] != 3 {
		t.Fatalf("issues %v", m.Issues)
	}
}

func TestChecksumMismatchStopsBeforeParsing(t *testing.T) {
	dir := t.TempDir()
	src := snomedInt(t, dir)
	b, _ := os.ReadFile(src)
	sum := sha256.Sum256(b)
	good := hex.EncodeToString(sum[:])

	m := run(t, Request{Sources: []string{src}, SHA256: []string{strings.ToUpper(good)}})
	requireOK(t, m)
	if m.Sources[0].SHA256 != good {
		t.Fatalf("sha %s", m.Sources[0].SHA256)
	}

	m = run(t, Request{Sources: []string{src}, SHA256: []string{strings.Repeat("0", 64)}})
	if m.OK || codes(m, format.Error)["checksum_mismatch"] != 1 || len(m.Files) != 0 || m.Format != "" {
		t.Fatalf("mismatch should stop before format resolution: %+v", m)
	}
	if _, err := Run(context.Background(), Request{Sources: []string{src}, SHA256: []string{good, good}}); err == nil {
		t.Fatal("expected an error for a sha256/source count mismatch")
	}
}

func TestManifestIsDeterministic(t *testing.T) {
	dir := t.TempDir()
	req := Request{Sources: []string{snomedInt(t, dir), snomedUS(t, dir)}, IngestDir: dir, Reason: "CHG-1"}
	a, _ := json.Marshal(run(t, req))
	b, _ := json.Marshal(run(t, req))
	if !bytes.Equal(a, b) {
		t.Fatal("two runs over the same sources produced different manifests")
	}
}

// ---- LOINC ----

func loincCode(n int) string {
	for d := 0; d < 10; d++ {
		c := fmt.Sprintf("%d-%d", n, d)
		if format.LOINCValid(c) {
			return c
		}
	}
	panic("no check digit")
}

func TestLOINC(t *testing.T) {
	dir := t.TempDir()
	hdr := `"LOINC_NUM","COMPONENT","PROPERTY","TIME_ASPCT","SYSTEM","SCALE_TYP","METHOD_TYP","CLASS","VersionLastChanged","CLASSTYPE","STATUS","SHORTNAME","LONG_COMMON_NAME","EXTRA"`
	row := func(code, status, ver string) string {
		return fmt.Sprintf(`"%s","Fixture analyte","MCnc","Pt","Ser","Qn","","CHEM","%s","1","%s","Fx","Fixture analyte, long name","x"`, code, ver, status)
	}
	a, b := loincCode(99990), loincCode(99991)
	src := mkzip(t, filepath.Join(dir, "Loinc_2.81.zip"), files{
		"LoincTable/Loinc.csv": hdr + "\n" + row(a, "ACTIVE", "2.80") + "\n" + row(b, "DEPRECATED", "2.81") + "\n",
		"LoincTable/MapTo.csv": "\"LOINC\",\"MAP_TO\",\"COMMENT\"\n\"" + b + "\",\"" + a + "\",\"\"\n\"" + b + "\",\"" + loincCode(99992) + "\",\"\"\n",
	})
	m := run(t, Request{Sources: []string{src}})
	requireOK(t, m)
	if m.Format != "loinc-csv" || m.Version != "2.81" || count(m, "active terms") != 1 {
		t.Fatalf("format %s version %s counts %v", m.Format, m.Version, m.Detected.Counts)
	}
	if codes(m, format.Warning)["unknown_loinc"] != 1 {
		t.Fatalf("expected unknown MAP_TO warning: %v", m.Issues)
	}

	bad := mkdir(t, filepath.Join(dir, "bad"), files{"Loinc.csv": hdr + "\n" + row("99990-0", "ACTIVE", "2.81") + "\n" + `"broken`})
	m = run(t, Request{Sources: []string{bad}, Version: "2.81"})
	if m.OK || codes(m, format.Error)["bad_loinc"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
}

// ---- RxNorm ----

func TestRxNorm(t *testing.T) {
	dir := t.TempDir()
	src := mkdir(t, filepath.Join(dir, "RxNorm_full_11032026"), files{
		"rrf/RXNCONSO.RRF": "9000001|ENG||||||9100001|||9000001|RXNORM|IN|9000001|fixturol||N|4096|\n" +
			"9000002|ENG||||||9100002|||9000002|RXNORM|SCD|9000002|fixturol 1 MG Oral Tablet||N|4096|\n",
		// RXCUI1 RXAUI1 STYPE1 REL RXCUI2 RXAUI2 STYPE2 RELA RUI SRUI SAB SL DIR RG SUPPRESS CVF
		"rrf/RXNREL.RRF":  strings.Join([]string{"9000001", "", "CUI", "RO", "9000002", "", "CUI", "ingredient_of", "R1", "", "RXNORM", "RXNORM", "", "", "N", ""}, "|") + "|\n",
		"rrf/RXNSAT.RRF":  "9000002|||9100002|AUI|9000002|AT1||RXN_HUMAN_DRUG|RXNORM|US|N|4096|\n",
		"rrf/RXNSAB.RRF":  mrsab("RXNORM", "RXNORM_FIX", "FIX", "0", "Y"),
		"rrf/RXNSTY.RRF":  "9000001|T121|A1.4|Pharmacologic Substance|AT2|4096|\n",
		"scripts/load.sh": "ignored",
	})
	m := run(t, Request{Sources: []string{src}})
	requireOK(t, m)
	if m.Format != "rxnorm-rrf" || m.Version != "11032026" || m.ReleaseDate != "2026-11-03" || count(m, "RXNORM atoms") != 2 {
		t.Fatalf("%s %s %s %v", m.Format, m.Version, m.ReleaseDate, m.Detected.Counts)
	}
}

// ---- UMLS ----

func gz(t *testing.T, s string) string {
	var b bytes.Buffer
	w := gzip.NewWriter(&b)
	_, _ = w.Write([]byte(s))
	_ = w.Close()
	return b.String()
}

// mrsab builds one MRSAB/RXNSAB row from the documented 25 columns.
func mrsab(rsab, vsab, sver, srl, curver string) string {
	f := make([]string, 25)
	f[0], f[1], f[2], f[3], f[4], f[5], f[6] = "C1", "C1", vsab, rsab, rsab+" fixture", rsab, sver
	f[13], f[19], f[20], f[21] = srl, "ENG", "UTF-8", curver
	return strings.Join(f, "|") + "|\n"
}

func umlsRelease(t *testing.T, dir string, consoRows int) string {
	conso := "C9000001|ENG|P|L1|PF|S1|Y|A90000001||F1||MDR|PT|90000001|Fixture event|3|N|256|\n" +
		"C9000001|ENG|S|L2|PF|S2|Y|A90000002||F2||MDR|LLT|90000002|Fixture event, other|3|N|256|\n" +
		"C9000002|ENG|P|L3|PF|S3|Y|A90000003||||LNC|LN|" + loincCode(99990) + "|Fixture analyte|0|N|256|\n"
	sab := mrsab("MDR", "MDR28_1", "28.1", "3", "Y") + mrsab("MDR", "MDR27_1", "27.1", "3", "N") + mrsab("LNC", "LNC281", "2.81", "0", "Y")
	files := files{
		"2026AB/META/MRFILES.RRF": "MRCONSO.RRF|Concepts|CUI,LAT,TS,LUI,STT,SUI,ISPREF,AUI,SAUI,SCUI,SDUI,SAB,TTY,CODE,STR,SRL,SUPPRESS,CVF|18|" + strconv.Itoa(consoRows) + "|0|\n" +
			"MRSAB.RRF|Sources|VCUI,RCUI,VSAB,RSAB,SON,SF,SVER,VSTART,VEND,IMETA,RMETA,SLC,SCC,SRL,TFR,CFR,CXTY,TTYL,ATNL,LAT,CENC,CURVER,SABIN,SSN,SCIT|25|3|0|\n",
		"2026AB/META/MRSAB.RRF":         sab,
		"2026AB/META/MRCONSO.RRF.aa.gz": gz(t, conso[:strings.Index(conso, "C9000002")]),
		"2026AB/META/MRCONSO.RRF.ab.gz": gz(t, conso[strings.Index(conso, "C9000002"):]),
		"2026AB/META/MRSTY.RRF":         "C9000001|T047|B2.2.1.2.1|Disease or Syndrome|AT3|256|\n",
	}
	return mkdir(t, filepath.Join(dir, "umls"), files)
}

func TestUMLSBySAB(t *testing.T) {
	src := umlsRelease(t, t.TempDir(), 3)
	m := run(t, Request{Sources: []string{src}, Format: "umls-rrf", SAB: "mdr"})
	requireOK(t, m)
	if m.CodeSystemID != "meddra" || m.SAB != "MDR" || m.Version != "28.1" || m.Origin != "umls" {
		t.Fatalf("system %s sab %s version %s", m.CodeSystemID, m.SAB, m.Version)
	}
	if codes(m, format.Info)["native_format_available"] != 1 {
		t.Fatalf("expected a pointer to the vendor format: %v", m.Issues)
	}
	for _, f := range m.Files {
		if f.Spec == "MRCONSO" {
			if f.Selected == nil || *f.Selected != 2 || f.Rows != 3 || len(f.Parts) != 2 {
				t.Fatalf("MRCONSO %+v", f)
			}
		}
	}

	// --system resolves the SAB; LNC → loinc.
	m = run(t, Request{Sources: []string{src}, Format: "umls-rrf", CodeSystemID: "loinc"})
	requireOK(t, m)
	if m.SAB != "LNC" || m.Version != "2.81" {
		t.Fatalf("sab %s version %s", m.SAB, m.Version)
	}

	// Whole Metathesaurus.
	m = run(t, Request{Sources: []string{src}, Format: "umls-rrf", CodeSystemID: "umls"})
	requireOK(t, m)
	if m.Version != "2026AB" {
		t.Fatalf("version %s", m.Version)
	}
}

func TestUMLSFailures(t *testing.T) {
	src := umlsRelease(t, t.TempDir(), 99)
	m := run(t, Request{Sources: []string{src}, Format: "umls-rrf", SAB: "MDR"})
	if m.OK || codes(m, format.Error)["row_count"] != 1 {
		t.Fatalf("expected MRFILES row count error: %v", m.Issues)
	}

	src = umlsRelease(t, t.TempDir(), 3)
	m = run(t, Request{Sources: []string{src}, Format: "umls-rrf"})
	if m.OK || codes(m, format.Error)["missing_sab"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
	m = run(t, Request{Sources: []string{src}, Format: "umls-rrf", CodeSystemID: "snomed"})
	if m.OK || codes(m, format.Error)["unknown_sab"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
	m = run(t, Request{Sources: []string{src}, Format: "loinc-csv", SAB: "LNC"})
	if m.OK || codes(m, format.Error)["sab_not_umls"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
}

// ---- ICD-10-CM / PCS ----

func order(n int, code, valid, text string) string {
	return fmt.Sprintf("%05d %-7s %s %-60s %s", n, code, valid, text, text)
}

func TestICD10CM(t *testing.T) {
	dir := t.TempDir()
	xml := `<?xml version="1.0" encoding="utf-8"?>
<ICD10CM.tabular>
  <version>2027</version>
  <chapter><name>1</name><desc>Fixture chapter</desc>
    <section id="U98-U98"><desc>Fixture section</desc>
      <diag><name>U98</name><desc>Fixture category</desc>
        <diag><name>U98.0</name><desc>Fixture leaf zero</desc></diag>
        <diag><name>U98.1</name><desc>Fixture leaf one</desc>
          <inclusionTerm><note>Fixture note</note></inclusionTerm>
        </diag>
      </diag>
    </section>
  </chapter>
</ICD10CM.tabular>
`
	src := mkdir(t, filepath.Join(dir, "icd10cm"), files{
		"icd10cm_order_2027.txt":         order(1, "U98", "0", "Fixture category") + "\r\n" + order(2, "U980", "1", "Fixture leaf zero") + "\r\n" + order(3, "U981", "1", "Fixture leaf one") + "\r\n",
		"icd10cm_tabular_2027.xml":       xml,
		"icd10cm_order_addenda_2027.txt": "ignored",
	})
	m := run(t, Request{Sources: []string{src}})
	if m.OK || codes(m, format.Error)["missing_validity"] != 1 || !strings.Contains(m.Issues[0].Message, "[2026-10-01,2027-10-01)") {
		t.Fatalf("expected missing validity with a suggestion: %v", m.Issues)
	}
	m = run(t, Request{Sources: []string{src}, Validity: "[2026-10-01,2027-10-01)"})
	requireOK(t, m)
	if m.Format != "icd10cm" || m.Version != "2027" || count(m, "tabular leaf codes") != 2 || count(m, "codes valid for submission") != 2 {
		t.Fatalf("%s %s %v", m.Format, m.Version, m.Detected.Counts)
	}
	if len(m.Issues) != 0 {
		t.Fatalf("unexpected issues %v", m.Issues)
	}

	for _, v := range []string{"2026-10-01", "[2027-10-01,2026-10-01)", "[2026-13-01,)"} {
		m = run(t, Request{Sources: []string{src}, Validity: v})
		if codes(m, format.Error)["bad_validity"] != 1 {
			t.Errorf("validity %q accepted: %v", v, m.Issues)
		}
	}

	bad := mkdir(t, filepath.Join(dir, "bad"), files{
		"icd10cm-order-April-2027.txt": order(2, "U98", "0", "x") + "\n" + order(1, "U98.0", "2", "y") + "\n",
	})
	m = run(t, Request{Sources: []string{bad}, Validity: "[2027-04-01,2027-10-01)"})
	got := codes(m, format.Error)
	if m.Version != "2027-04" || got["order_not_increasing"] != 1 || got["bad_code"] != 1 || got["bad_flag"] != 1 {
		t.Fatalf("version %s errors %v", m.Version, got)
	}
}

func TestICD10PCSNotDOSValidityRules(t *testing.T) {
	src := mkdir(t, t.TempDir(), files{
		"icd10pcs_order_2027.txt": order(1, "0Z9", "0", "Fixture table") + "\n" + order(2, "0Z9ZZZZ", "1", "Fixture procedure") + "\n" + order(3, "0Z9ZZZI", "1", "Has an I") + "\n",
	})
	m := run(t, Request{Sources: []string{src}, Validity: "[2026-10-01,2027-10-01)"})
	if m.Format != "icd10pcs" || codes(m, format.Error)["bad_code"] != 1 {
		t.Fatalf("%s %v", m.Format, m.Issues)
	}
	// A non-DOS system rejects --validity.
	cvx := mkdir(t, t.TempDir(), files{"cvx.txt": "990|Fixture vaccine|Fixture vaccine, full||Active|1|False|1/2/2026\n"})
	m = run(t, Request{Sources: []string{cvx}, Validity: "[2026-01-01,)"})
	if codes(m, format.Error)["unexpected_validity"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
}

// ---- HCPCS / CPT ----

func TestHCPCS(t *testing.T) {
	line := func(code string, seq int, ric, long string) string {
		return fmt.Sprintf("%-5s%05d%s%-80s%-28s", code, seq, ric, long, "Fixture")
	}
	src := mkzip(t, filepath.Join(t.TempDir(), "HCPC2027_JAN_ANWEB.zip"), files{
		"HCPC2027_JAN_ANWEB_v2.txt": line("W0001", 100, "3", "Fixture supply") + "\r\n" + line("W0001", 200, "4", "continued") + "\r\n" +
			line("Z9", 100, "7", "Fixture modifier") + "\r\n" + line("W00X1", 100, "3", "bad") + "\r\n",
	})
	m := run(t, Request{Sources: []string{src}, Validity: "[2027-01-01,2027-04-01)"})
	if m.Format != "hcpcs-anweb" || m.Version != "2027-JAN" || m.Detected.ValiditySuggestion != "[2027-01-01,2027-04-01)" {
		t.Fatalf("%s %s %s", m.Format, m.Version, m.Detected.ValiditySuggestion)
	}
	if codes(m, format.Error)["bad_code"] != 1 || count(m, "procedure codes") != 2 || count(m, "modifiers") != 1 {
		t.Fatalf("%v %v", m.Issues, m.Detected.Counts)
	}
}

func TestCPT(t *testing.T) {
	src := mkdir(t, filepath.Join(t.TempDir(), "CPT 2027 Data Files"), files{
		"LONGULT.txt": "00001\tFixture procedure one\r\n0001T\tFixture tracking code\r\n",
		"SHORTU.txt":  "00001 FIXTURE ONE\r\n00002 NOT IN LONG\r\n",
		"ClinicianDescriptor/ClinicianDescriptor.txt": "Concept Id\tCPT Code\tClinician Descriptor Id\tClinician Descriptor\r\n1\t00001\t1\tFixture descriptor\r\n",
	})
	m := run(t, Request{Sources: []string{src}, Validity: "[2027-01-01,2028-01-01)"})
	requireOK(t, m)
	if m.Format != "cpt-ama" || m.Version != "2027" || count(m, "codes") != 2 || codes(m, format.Warning)["unknown_code"] != 1 {
		t.Fatalf("%s %s %v %v", m.Format, m.Version, m.Detected.Counts, m.Issues)
	}
}

// ---- CDC / NUCC / MedDRA / FHIR ----

func TestCDCAndNUCC(t *testing.T) {
	dir := t.TempDir()
	cvx := mkdir(t, filepath.Join(dir, "cvx"), files{"web_cvx.txt": "990|Fixture A|Fixture vaccine A||Active|1|False|1/2/2026\n991|Fixture B|Fixture vaccine B||Inactive|2|False|3/4/2026\n"})
	m := run(t, Request{Sources: []string{cvx}})
	requireOK(t, m)
	if m.CodeSystemID != "cvx" || m.Version != "20260304" {
		t.Fatalf("%s %s", m.CodeSystemID, m.Version)
	}
	mvx := mkdir(t, filepath.Join(dir, "mvx"), files{"mvx.txt": "QQA|Fixture Manufacturer||Active|5/6/2026\nQQA|Duplicate||Active|5/6/2026\n"})
	m = run(t, Request{Sources: []string{mvx}})
	if m.CodeSystemID != "mvx" || codes(m, format.Error)["duplicate_code"] != 1 {
		t.Fatalf("%s %v", m.CodeSystemID, m.Issues)
	}
	nucc := mkdir(t, filepath.Join(dir, "nucc"), files{"nucc_taxonomy_251.csv": "Code,Grouping,Classification,Specialization,Definition,Notes,Display Name,Section\n999999999X,Fixture group,Fixture class,,,,Fixture,Individual\nBAD,Fixture group,Fixture class,,,,Fixture,Individual\n"})
	m = run(t, Request{Sources: []string{nucc}})
	if m.CodeSystemID != "nucc" || m.Version != "25.1" || codes(m, format.Error)["bad_code"] != 1 {
		t.Fatalf("%s %s %v", m.CodeSystemID, m.Version, m.Issues)
	}
}

func TestMedDRA(t *testing.T) {
	src := mkdir(t, t.TempDir(), files{
		"MedAscii/meddra_release.asc": "28.1$English$\n",
		"MedAscii/soc.asc":            "90000010$Fixture SOC$Fix$$$$$$$$\n",
		"MedAscii/hlgt.asc":           "90000020$Fixture HLGT$$$$$$$$\n",
		"MedAscii/hlt.asc":            "90000030$Fixture HLT$$$$$$$$\n",
		"MedAscii/pt.asc":             "90000040$Fixture PT$$90000010$$$$$$$$\n90000041$Orphan PT$$90000019$$$$$$$$\n",
		"MedAscii/llt.asc":            "90000040$Fixture PT$90000040$$$$$$$Y$$\n90000050$Fixture LLT$90000040$$$$$$$N$$\n",
		"MedAscii/mdhier.asc":         "90000040$90000030$90000020$90000010$Fixture PT$Fixture HLT$Fixture HLGT$Fixture SOC$Fix$$90000010$Y$\n",
	})
	m := run(t, Request{Sources: []string{src}})
	if m.Format != "meddra-ascii" || m.CodeSystemID != "meddra" || m.Version != "28.1" {
		t.Fatalf("%s %s %s", m.Format, m.CodeSystemID, m.Version)
	}
	if got := codes(m, format.Error); len(got) != 1 || got["unknown_code"] != 1 {
		t.Fatalf("expected one unknown SOC reference: %v", m.Issues)
	}
	if count(m, "current LLTs") != 1 {
		t.Fatalf("counts %v", m.Detected.Counts)
	}
}

func TestFHIRCodeSystem(t *testing.T) {
	dir := t.TempDir()
	cs := `{"resourceType":"CodeSystem","url":"http://hl7.org/fhir/sid/cvx","version":"2026-05","date":"2026-05-01T00:00:00Z",
	        "content":"complete","count":3,"concept":[{"code":"990","display":"Fixture A","concept":[{"code":"991","display":"Fixture B"}]},{"code":"992","display":"Fixture C"}]}`
	src := mkdir(t, filepath.Join(dir, "a"), files{"cvx-codesystem.json": cs})

	// Not auto-detected: JSON is too generic.
	m := run(t, Request{Sources: []string{src}})
	if codes(m, format.Error)["unknown_format"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
	m = run(t, Request{Sources: []string{src}, Format: "fhir-codesystem"})
	requireOK(t, m)
	if m.CodeSystemID != "cvx" || m.Version != "2026-05" || m.ReleaseDate != "2026-05-01" || count(m, "concepts") != 3 {
		t.Fatalf("%s %s %s %v", m.CodeSystemID, m.Version, m.ReleaseDate, m.Detected.Counts)
	}
	m = run(t, Request{Sources: []string{src}, Format: "fhir-codesystem", CodeSystemID: "nucc"})
	if codes(m, format.Error)["format_system_mismatch"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}

	frag := mkdir(t, filepath.Join(dir, "b"), files{"x.json": strings.Replace(strings.Replace(cs, `"complete"`, `"fragment"`, 1), `"count":3`, `"count":4`, 1)})
	m = run(t, Request{Sources: []string{frag}, Format: "fhir-codesystem"})
	got := codes(m, format.Error)
	if got["not_complete"] != 1 || got["count_mismatch"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}
}

func TestUnknownFormatAndIssueCap(t *testing.T) {
	src := mkdir(t, t.TempDir(), files{"readme.txt": "nothing to see"})
	m := run(t, Request{Sources: []string{src}})
	if m.OK || codes(m, format.Error)["unknown_format"] != 1 {
		t.Fatalf("issues %v", m.Issues)
	}

	var rows []string
	for i := 0; i < 50; i++ {
		rows = append(rows, fmt.Sprintf("%05d %-7s 1 %-60s %s", i+1, "bad!", "x", "x"))
	}
	src = mkdir(t, t.TempDir(), files{"icd10pcs_order_2027.txt": strings.Join(rows, "\n")})
	m = run(t, Request{Sources: []string{src}, Validity: "[2026-10-01,2027-10-01)", MaxIssues: 5})
	if codes(m, format.Error)["bad_code"] != 5 || m.Errors != 50 || len(m.Suppressed) != 1 || m.Suppressed[0].Count != 45 {
		t.Fatalf("errors %d suppressed %+v", m.Errors, m.Suppressed)
	}
}
