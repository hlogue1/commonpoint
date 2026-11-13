package impact

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "impact",
		Short: "Diff report for terminology releases",
	}
	return cmd
}
