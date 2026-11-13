package ingest

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "ingest",
		Short: "Ingest release files (RF2, RRF, CSV, etc.)",
		Args:  cobra.ArbitraryArgs,
	}

	cmd.Flags().StringP("termSystem", "s", "", "Term system code")

	if err := cmd.MarkFlagRequired("termSystem"); err != nil {
		panic(err)
	}

	return cmd
}
