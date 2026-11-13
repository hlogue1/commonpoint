package build

import (
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/build/deploy"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/build/diff"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/build/release"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/build/verify"
	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "build",
		Short: "Manage CommonPoint Build Configuration",
	}

	cmd.AddCommand(deploy.NewCommand())
	cmd.AddCommand(diff.NewCommand())
	cmd.AddCommand(release.NewCommand())
	cmd.AddCommand(verify.NewCommand())

	return cmd
}
