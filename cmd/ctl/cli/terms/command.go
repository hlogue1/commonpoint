package terms

import (
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/activate"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/clean"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/impact"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/ingest"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/install"
	pkg "github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/package"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/rollback"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/validate"
	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "terms",
		Short: "Manage CommonPoint Terminology Sets",
	}

	cmd.AddCommand(activate.NewCommand())
	cmd.AddCommand(clean.NewCommand())
	cmd.AddCommand(impact.NewCommand())
	cmd.AddCommand(ingest.NewCommand())
	cmd.AddCommand(install.NewCommand())
	cmd.AddCommand(pkg.NewCommand())
	cmd.AddCommand(rollback.NewCommand())
	cmd.AddCommand(validate.NewCommand())

	return cmd
}
