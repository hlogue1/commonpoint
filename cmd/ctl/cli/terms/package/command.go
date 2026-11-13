package pkg

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "package",
		Short: "Export terminology artifact",
	}
	return cmd
}
