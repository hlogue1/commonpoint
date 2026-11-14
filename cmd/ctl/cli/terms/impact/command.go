// SPDX-License-Identifier: GPL-3.0-or-later

package impact

import (
	"errors"

	"github.com/spf13/cobra"
)

func NewCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:          "impact",
		Short:        "Diff report for terminology releases",
		SilenceUsage: true,
		RunE: func(cmd *cobra.Command, args []string) error {
			return errors.New("not implemented: will call AdminService.DiffVersions (PLAN M4)")
		},
	}
	return cmd
}
