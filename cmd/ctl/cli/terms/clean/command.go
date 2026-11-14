// SPDX-License-Identifier: GPL-3.0-or-later

package clean

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "clean",
		Short:        "Remove unused terminology releases",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.RetireVersion (PLAN M3)")
		},
	}
	return cmd
}
