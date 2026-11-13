package clean

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "clean",
		Short: "Remove unused terminology releases",
	}
	return cmd
}
