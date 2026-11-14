// SPDX-License-Identifier: GPL-3.0-or-later

package install

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "install",
		Short:        "Install new terminology release",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.StartInstall (PLAN M3)")
		},
	}
	return cmd
}
