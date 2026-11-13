package install

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "install",
		Short: "Install new terminology release",
	}
	return cmd
}
