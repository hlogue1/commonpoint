package verify

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "verify",
		Short: "Detect Drift Between CommonPoint Build Configuration and Production Environment",
	}
	return cmd
}
