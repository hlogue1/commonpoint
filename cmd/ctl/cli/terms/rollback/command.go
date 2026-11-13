package rollback

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "rollback",
		Short: "Revert terminology changes",
	}
	return cmd
}
