// SPDX-License-Identifier: GPL-3.0-or-later

package activate

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "activate",
		Short:        "Activate terminology release",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.ActivateVersion (PLAN M4)")
		},
	}
	return cmd
}
