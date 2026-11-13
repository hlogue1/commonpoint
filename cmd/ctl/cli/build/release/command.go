package release

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "release",
		Short: "Package CommonPoint Build Configuration Release",
	}
	return cmd
}
