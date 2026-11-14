// SPDX-License-Identifier: GPL-3.0-or-later

// Package inspect implements `ctl terms inspect`: a quick look at release files.
package inspect

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"text/tabwriter"

	"github.com/hlogue1/commonpoint/internal/terms/loader/format"
	"github.com/hlogue1/commonpoint/internal/terms/loader/ingest"
	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	var (
		formatName, sab, output string
		listFiles               bool
	)
	cmd := &cobra.Command{
		Use:   "inspect [flags] SOURCE...",
		Short: "Show which formats release files match and what version they carry",
		Long: `Inspect release sources without reading them in full: the formats they match,
the files each format would read, and the metadata the file names carry. For UMLS it
lists the sources (SABs) in MRSAB with their versions and restriction levels.`,
		Args:         cobra.MinimumNArgs(1),
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			in, err := ingest.Inspect(args, formatName, format.Options{SAB: strings.ToUpper(sab)})
			if err != nil {
				return err
			}
			w := cmd.OutOrStdout()
			if output == "json" {
				enc := json.NewEncoder(w)
				enc.SetIndent("", "  ")
				return enc.Encode(in)
			}
			tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
			for i, s := range in.Sources {
				fmt.Fprintf(w, "source %d: %s (%s, %d files)\n", i, s.Path, s.Kind, len(s.Files))
				if listFiles {
					for _, f := range s.Files {
						fmt.Fprintf(w, "  %s\n", f)
					}
				}
			}
			if len(in.Candidates) == 0 {
				fmt.Fprintln(w, "\nno known format matches; see `ctl terms formats`")
				return nil
			}
			for _, c := range in.Candidates {
				fmt.Fprintf(w, "\nformat %s (%s)", c.Format, c.Origin)
				if len(c.Systems) > 0 {
					fmt.Fprintf(w, " -> %s", strings.Join(c.Systems, ", "))
				}
				fmt.Fprintln(w)
				var ids []string
				for id := range c.Matched {
					ids = append(ids, id)
				}
				sort.Strings(ids)
				for _, id := range ids {
					fmt.Fprintf(tw, "  %s\t%d file(s)\n", id, c.Matched[id])
				}
				md := c.Metadata
				for _, kv := range [][2]string{{"version", md.Version}, {"release date", md.ReleaseDate},
					{"FHIR version URI", md.FHIRVersionURI}, {"suggested validity", md.ValiditySuggestion},
					{"packages", strings.Join(md.Packages, ", ")}} {
					if kv[1] != "" {
						fmt.Fprintf(tw, "  %s\t%s\n", kv[0], kv[1])
					}
				}
				_ = tw.Flush()
				for _, n := range md.Notes {
					fmt.Fprintf(w, "  note: %s\n", n)
				}
				if len(md.SABs) > 0 {
					fmt.Fprintln(w, "  UMLS sources (current versions):")
					for _, s := range md.SABs {
						if !s.Current {
							continue
						}
						fmt.Fprintf(tw, "    %s\t%s\tSRL %s\t%s\t%s\n", s.RSAB, s.SVER, s.SRL, orDash(s.CodeSystemID), s.Name)
					}
					_ = tw.Flush()
				}
			}
			return nil
		},
	}
	cmd.Flags().StringVarP(&formatName, "format", "f", "", "only check this format")
	cmd.Flags().StringVar(&sab, "sab", "", "UMLS source abbreviation to describe")
	cmd.Flags().BoolVar(&listFiles, "files", false, "list every file in each source")
	cmd.Flags().StringVarP(&output, "output", "o", "text", "output: text or json")
	return cmd
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
