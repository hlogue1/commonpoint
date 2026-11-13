package diff

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "diff",
		Short: "View CommonPoint Build Configuration Change Report",
	}
	return cmd
}
