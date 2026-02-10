package cmd

import (
	"context"
	"fmt"
	"log/slog"
	"os"

	"ops-cli/internal/incident"

	"github.com/spf13/cobra"
)

var dryRun bool

// responseCmd represents the response command
var responseCmd = &cobra.Command{
	Use:   "response",
	Short: "Detect anomalies and execute self-healing actions",
	Long: `Automated Incident Response Framework.
Checks system health (Load, Services) and performs remediation if authorized.

Example:
  ops-cli response --dry-run=false  # Execute remediations
  ops-cli response                  # Dry-run mode (default)`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		if ctx == nil {
			ctx = context.Background()
		}

		slog.Info("Starting Incident Response Engine", "dry_run", dryRun)

		// Define the standard set of checks for a web server
		checks := []incident.Check{
			&incident.LoadCheck{MaxLoad: 5.0}, // Alert if load > 5
			&incident.ServiceCheck{ServiceName: "httpd", Port: 80},
			&incident.ServiceCheck{ServiceName: "mysql", Port: 3306},
			&incident.MinerCheck{}, // Detect active miners
			&incident.OOMCheck{},   // Check for kernel OOM events
			&incident.KillerProcessCheck{}, // Detect system killer daemons
		}

		engine := &incident.Engine{
			Checks: checks,
			DryRun: dryRun,
		}

		incidents, err := engine.Run(ctx)
		if err != nil {
			return fmt.Errorf("engine failure: %w", err)
		}

		if len(incidents) == 0 {
			slog.Info("System Healthy. No incidents detected.")
			return nil
		}

		for _, inc := range incidents {
			slog.Warn("Incident Detected", "check", inc.CheckName, "error", inc.Description)

			if inc.Remediation != nil {
				if dryRun {
					slog.Info("Dry-Run: Would execute remediation", "action", inc.Remediation.Name())
				} else {
					slog.Info("Executing Remediation", "action", inc.Remediation.Name())
					if err := inc.Remediation.Execute(ctx); err != nil {
						slog.Error("Remediation Failed", "action", inc.Remediation.Name(), "error", err)
					} else {
						slog.Info("Remediation Successful", "action", inc.Remediation.Name())
					}
				}
			} else {
				slog.Info("No automated remediation available for this incident")
			}
		}

		// If we found incidents but didn't error out, we might want to return a non-zero exit code
		// to signal monitoring systems, even if we handled them.
		if len(incidents) > 0 {
			os.Exit(1)
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(responseCmd)
	responseCmd.Flags().BoolVar(&dryRun, "dry-run", true, "Simulate actions without execution")
}
