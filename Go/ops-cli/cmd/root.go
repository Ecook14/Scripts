package cmd

import (
	"context"
	"fmt"
	//"os"

	"github.com/spf13/cobra"
)

var rootCmd = &cobra.Command{
	Use:   "ops-cli",
	Short: "A unified system administration CLI",
	Long: `ops-cli is a modern, Go-based replacement for existing shell scripts.
It includes modules for:
 - System Health Checks
 - Log Analysis
 - Security Hardening
 - Resource Optimization
`,
	Run: func(cmd *cobra.Command, args []string) {
		fmt.Println("Welcome to ops-cli! Use --help to see available commands.")
	},
}

const (
	// ExitFailure indicates a general error
	ExitFailure = 1
)

func Execute(ctx context.Context) error {
	return rootCmd.ExecuteContext(ctx)
}

var jsonOutput bool

func init() {
	rootCmd.PersistentFlags().BoolVar(&jsonOutput, "json", false, "Enable structured JSON output")
}
