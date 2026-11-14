// SPDX-License-Identifier: GPL-3.0-or-later

package terms

import (
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/activate"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/clean"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/formats"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/impact"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/ingest"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/inspect"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms/install"
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
	cmd.AddCommand(formats.NewCommand())
	cmd.AddCommand(impact.NewCommand())
	cmd.AddCommand(ingest.NewCommand())
	cmd.AddCommand(inspect.NewCommand())
	cmd.AddCommand(install.NewCommand())
	cmd.AddCommand(rollback.NewCommand())
	cmd.AddCommand(validate.NewCommand())

	return cmd
}
