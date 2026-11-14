// SPDX-License-Identifier: GPL-3.0-or-later

package rollback

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "rollback",
		Short:        "Revert terminology changes",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.RollbackVersion (PLAN M4)")
		},
	}
	return cmd
}
