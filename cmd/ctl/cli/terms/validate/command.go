// SPDX-License-Identifier: GPL-3.0-or-later

package validate

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "validate",
		Short:        "Validate terminology install",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.ValidateVersion (PLAN M3)")
		},
	}
	return cmd
}
