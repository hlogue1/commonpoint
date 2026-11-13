package envman

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "envman",
		Short: "Manage CommonPoint Environments",
	}
	return cmd
}
