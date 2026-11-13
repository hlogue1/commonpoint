package activate

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "activate",
		Short: "Activate terminology release",
	}
	return cmd
}
