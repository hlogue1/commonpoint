package deploy

import "github.com/spf13/cobra"

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "deploy",
		Short: "Deploy CommonPoint Build Configuration to Production Environment",
	}
	return cmd
}
