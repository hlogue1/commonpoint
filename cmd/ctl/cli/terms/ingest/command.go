package ingest

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ingest",
		Short: "Ingest release files (RF2, RRF, CSV, etc.)",
	}
	return cmd
}
