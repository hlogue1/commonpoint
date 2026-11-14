package cli

import (
	"os"

	"github.com/hlogue1/commonpoint/cmd/ctl/cli/build"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/envman"
	"github.com/hlogue1/commonpoint/cmd/ctl/cli/terms"
	"github.com/spf13/cobra"
)

var (
	verbose bool
)

// rootCmd represents the base command when called without any subcommands
var rootCmd = &cobra.Command{
	Use:   "ctl",
	Short: "CommonPoint EHR Control Interface",
}

func Execute() {
	err := rootCmd.Execute()
	if err != nil {
		os.Exit(1)
	}
}

func init() {
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "verbose output")
	rootCmd.AddCommand(build.NewCommand())
	rootCmd.AddCommand(envman.NewCommand())
	rootCmd.AddCommand(terms.NewCommand())
}
