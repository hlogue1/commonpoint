// SPDX-License-Identifier: GPL-3.0-or-later

// Package ingest implements `ctl terms ingest`: verify a release and write its manifest.
package ingest

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"
	"text/tabwriter"

	"github.com/hlogue1/commonpoint/internal/terms/loader/format"
	"github.com/hlogue1/commonpoint/internal/terms/loader/ingest"
	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	var (
		req      ingest.Request
		manifest string
		output   string
	)
	cmd := &cobra.Command{
		Use:   "ingest [flags] SOURCE...",
		Short: "Verify release files (RF2, RRF, CSV, etc.) and write an ingest manifest",
		Long: `Verify a terminology release before it is registered.

SOURCE is a release archive (.zip), an extracted directory, or a single file. Pass several
sources for layered releases (e.g. SNOMED CT International + US Edition).

ingest checks each source's SHA-256 (against --sha256 when given), recognizes the format
(publisher formats and UMLS Metathesaurus RRF; see "ctl terms formats"), reads every file
once to validate structure, identifiers and cross-file references, and reconciles the
version metadata with what the release says about itself. The manifest it writes carries
the AdminService StartIngest fields plus per-file checksums and counts.

UMLS: use --format umls-rrf with --sab (e.g. SNOMEDCT_US, LNC, RXNORM) or --system;
"--system umls" ingests the whole Metathesaurus.

Registration (AdminService.StartIngest) needs the terms server and isn't wired yet
(PLAN M2/M3). Promotion between terminology environments is done by a separate ETL.`,
		Example: `  ctl terms ingest --manifest snomed.json data/SnomedCT_InternationalRF2_PRODUCTION_20260601.zip data/SnomedCT_ManagedServiceUS_PRODUCTION_US1000124_20260901.zip
  ctl terms ingest --system icd10cm --validity '[2026-10-01,2027-10-01)' data/icd10cm/
  ctl terms ingest --format umls-rrf --sab MDR data/umls/2026AB/META
  ctl terms ingest --format fhir-codesystem --system nucc vendor/taxonomy.json`,
		Args:         cobra.MinimumNArgs(1),
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			req.Sources = args
			if verbose, _ := cmd.Flags().GetBool("verbose"); verbose {
				req.Progress = func(r format.FileResult) {
					fmt.Fprintf(cmd.ErrOrStderr(), "read %d:%s (%d rows)\n", r.Source, r.Path, r.Rows)
				}
			}
			m, err := ingest.Run(cmd.Context(), req)
			if err != nil {
				return err
			}
			if manifest != "" {
				if err := writeJSON(manifest, m); err != nil {
					return err
				}
			}
			switch output {
			case "json":
				enc := json.NewEncoder(cmd.OutOrStdout())
				enc.SetIndent("", "  ")
				if err := enc.Encode(m); err != nil {
					return err
				}
			case "text":
				printManifest(cmd.OutOrStdout(), m, manifest)
			default:
				return fmt.Errorf("--output must be text or json")
			}
			if !m.OK {
				return fmt.Errorf("ingest failed: %d errors", m.Errors)
			}
			return nil
		},
	}
	f := cmd.Flags()
	f.StringVarP(&req.CodeSystemID, "system", "s", "", "code system id (code_system.id), e.g. snomed, icd10cm; derived from the format or SAB when omitted")
	f.StringVarP(&req.Format, "format", "f", "", "release format (see `ctl terms formats`); detected when omitted")
	f.StringVar(&req.SAB, "sab", "", "UMLS source abbreviation to ingest (umls-rrf only)")
	f.StringVar(&req.Version, "version", "", "publisher's version string; detected when omitted")
	f.StringVar(&req.ReleaseDate, "release-date", "", "release date, YYYY-MM-DD; detected when omitted")
	f.StringVar(&req.FHIRVersionURI, "fhir-version-uri", "", "FHIR version URI (SNOMED edition URI); detected when omitted")
	f.StringVar(&req.Validity, "validity", "", "date-of-service range for billing code sets, e.g. '[2026-10-01,2027-10-01)'")
	f.StringSliceVar(&req.SHA256, "sha256", nil, "expected SHA-256 per source, in source order (repeatable)")
	f.StringVar(&req.Reason, "reason", "", "ticket / change number recorded with the version")
	f.StringVar(&req.IngestDir, "ingest-dir", os.Getenv("CP_TERMS_INGEST_DIR"), "server ingest directory; manifest source paths are relative to it ($CP_TERMS_INGEST_DIR)")
	f.IntVar(&req.MaxIssues, "max-issues", 20, "issues kept per file and issue code (0 = all); totals always count everything")
	f.StringVarP(&manifest, "manifest", "m", "", "write the manifest JSON to this file")
	f.StringVarP(&output, "output", "o", "text", "output: text or json")
	return cmd
}

func writeJSON(path string, v any) error {
	b, err := json.MarshalIndent(v, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(b, '\n'), 0o644)
}

func printManifest(w io.Writer, m *ingest.Manifest, manifestPath string) {
	tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
	kv := func(k, v string) {
		if v != "" {
			fmt.Fprintf(tw, "%s\t%s\n", k, v)
		}
	}
	if m.Format != "" {
		kv("format", fmt.Sprintf("%s (%s, %s)", m.Format, m.Origin, m.SourceFormat))
	}
	kv("code system", m.CodeSystemID)
	kv("UMLS SAB", m.SAB)
	kv("version", m.Version)
	kv("release date", m.ReleaseDate)
	kv("FHIR version URI", m.FHIRVersionURI)
	kv("validity", m.Validity)
	if m.Validity == "" {
		kv("validity (suggested)", m.Detected.ValiditySuggestion)
	}
	kv("packages", strings.Join(m.Detected.Packages, ", "))
	_ = tw.Flush()

	fmt.Fprintln(w, "\nsources:")
	for i, s := range m.Sources {
		fmt.Fprintf(tw, "  %d\t%s\t%s\t%s\tsha256 %s\n", i, s.Path, s.Kind, humanBytes(s.Bytes), s.SHA256)
	}
	_ = tw.Flush()

	if len(m.Files) > 0 {
		fmt.Fprintln(w, "\nfiles:")
		for _, f := range m.Files {
			sel := ""
			if f.Selected != nil {
				sel = fmt.Sprintf("%d for SAB", *f.Selected)
			}
			fmt.Fprintf(tw, "  %s\t%d:%s\t%d rows\t%s\n", f.Spec, f.Source, f.Path, f.Rows, sel)
		}
		_ = tw.Flush()
	}
	if len(m.Detected.Counts) > 0 {
		fmt.Fprintln(w, "\ncounts:")
		for _, c := range m.Detected.Counts {
			fmt.Fprintf(tw, "  %s\t%d\n", c.Name, c.Value)
		}
		_ = tw.Flush()
	}
	if len(m.Detected.Notes) > 0 {
		fmt.Fprintln(w, "\nnotes:")
		for _, n := range m.Detected.Notes {
			fmt.Fprintf(w, "  %s\n", n)
		}
	}
	if len(m.Ignored) > 0 {
		fmt.Fprintf(w, "\n%d files in the sources aren't read by %s.\n", len(m.Ignored), m.Format)
	}
	if len(m.Issues) > 0 {
		fmt.Fprintln(w, "\nissues:")
		for _, i := range m.Issues {
			loc := i.File
			if i.Line > 0 {
				loc = fmt.Sprintf("%s:%d", loc, i.Line)
			}
			if loc != "" {
				loc += ": "
			}
			fmt.Fprintf(w, "  %-7s %s %s%s\n", strings.ToUpper(string(i.Severity)), i.Code, loc, i.Message)
		}
	}
	for _, s := range m.Suppressed {
		fmt.Fprintf(w, "  … %d more %s %s in %s\n", s.Count, s.Severity, s.Code, s.File)
	}

	fmt.Fprintln(w)
	if m.OK {
		fmt.Fprintf(w, "OK: %d warnings.", m.Warnings)
		if manifestPath != "" {
			fmt.Fprintf(w, " Manifest written to %s.", manifestPath)
		}
		fmt.Fprintln(w, "\nRegistration (AdminService.StartIngest) isn't available until the terms server lands (PLAN M2/M3).")
	} else {
		fmt.Fprintf(w, "FAILED: %d errors, %d warnings.\n", m.Errors, m.Warnings)
	}
}

func humanBytes(n int64) string {
	const unit = 1024
	if n < unit {
		return fmt.Sprintf("%d B", n)
	}
	div, exp := int64(unit), 0
	for x := n / unit; x >= unit; x /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %ciB", float64(n)/float64(div), "KMGTPE"[exp])
}
