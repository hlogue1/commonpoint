// SPDX-License-Identifier: GPL-3.0-or-later

// Package formats implements `ctl terms formats`: the release formats ingest understands.
package formats

import (
	"fmt"
	"strings"
	"text/tabwriter"

	"github.com/hlogue1/commonpoint/internal/terms/loader/format"
	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	var detail bool
	cmd := &cobra.Command{
		Use:   "formats [FORMAT]",
		Short: "List the release formats ingest understands (vendor and UMLS)",
		Args:  cobra.MaximumNArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			w := cmd.OutOrStdout()
			fs := format.All()
			if len(args) == 1 {
				f := format.Lookup(args[0])
				if f == nil {
					return fmt.Errorf("unknown format %q", args[0])
				}
				fs, detail = []*format.Format{f}, true
			}
			tw := tabwriter.NewWriter(w, 0, 0, 2, ' ', 0)
			fmt.Fprintln(tw, "FORMAT\tORIGIN\tCODE SYSTEMS\tPUBLISHER\tDESCRIPTION")
			for _, f := range fs {
				systems := strings.Join(f.CodeSystems, ",")
				if f.Origin == format.UMLS {
					systems = "by --sab"
				} else if systems == "" {
					systems = "from resource url"
				}
				fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", f.Name, f.Origin, systems, f.Publisher, f.Title)
			}
			_ = tw.Flush()
			if !detail {
				return nil
			}
			for _, f := range fs {
				fmt.Fprintf(w, "\n%s files:\n", f.Name)
				for _, s := range f.Files {
					need := "optional"
					switch {
					case s.Required:
						need = "required"
					case s.OneOf != "":
						need = "one of " + s.OneOf
					}
					fmt.Fprintf(tw, "  %s\t%s\t%s\n", s.ID, need, s.Pattern)
				}
				_ = tw.Flush()
			}
			return nil
		},
	}
	cmd.Flags().BoolVar(&detail, "files", false, "also list the files each format reads")
	return cmd
}
