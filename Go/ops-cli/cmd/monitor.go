package cmd

import (
	"fmt"
	"log/slog"
	"ops-cli/internal/monitor"
	"strings"

	"github.com/spf13/cobra"
)

var (
	herdThreshold int
	exportAddr    string
)

// monitorCmd represents the monitor command
var monitorCmd = &cobra.Command{
	Use:   "monitor",
	Short: "High-Availability Monitoring Sidecar",
	Long:  `Monitor TCP backlog, socket states, and thundering herd patterns.`,
}

var connCmd = &cobra.Command{
	Use:   "connections",
	Short: "Show TCP connection statistics",
	RunE: func(cmd *cobra.Command, args []string) error {
		sockets, err := monitor.GetTCPConnections()
		if err != nil {
			return fmt.Errorf("failed to get connections: %w", err)
		}

		report := monitor.AnalyzeConnections(sockets)
		if jsonOutput {
			render(report, "")
			return nil
		}

		fmt.Printf("TCP Statistics:\n")
		fmt.Printf("Total Connections: %d\n", report.TotalConnections)
		fmt.Printf("By State:\n")
		for state, count := range report.ByState {
			fmt.Printf("  %-12s: %d\n", state, count)
		}
		return nil
	},
}

var backlogCmd = &cobra.Command{
	Use:   "backlog",
	Short: "Report on LISTEN queue health",
	RunE: func(cmd *cobra.Command, args []string) error {
		sockets, err := monitor.GetTCPConnections()
		if err != nil {
			return fmt.Errorf("failed to get connections: %w", err)
		}

		report := monitor.AnalyzeConnections(sockets)
		if jsonOutput {
			render(report.HighBacklogPorts, "")
			return nil
		}

		if len(report.HighBacklogPorts) == 0 {
			slog.Info("All listen queues are healthy.")
			return nil
		}

		slog.Warn("Backlog detected on ports", "ports", report.HighBacklogPorts)
		return nil
	},
}

var thunderingCmd = &cobra.Command{
	Use:   "thundering",
	Short: "Detect Thundering Herd patterns",
	RunE: func(cmd *cobra.Command, args []string) error {
		sockets, err := monitor.GetTCPConnections()
		if err != nil {
			return fmt.Errorf("failed to get connections: %w", err)
		}

		detected, msg := monitor.DetectThunderingHerd(sockets, herdThreshold)
		if jsonOutput {
			render(map[string]interface{}{"detected": detected, "message": msg}, "")
			return nil
		}

		if detected {
			slog.Warn(msg)
		} else {
			slog.Info("No thundering herd detected.")
		}
		return nil
	},
}

var serveCmd = &cobra.Command{
	Use:   "serve",
	Short: "Start Prometheus metrics exporter",
	RunE: func(cmd *cobra.Command, args []string) error {
		exporter := monitor.NewExporter()

		slog.Info("Starting metrics exporter", "addr", exportAddr)

		// Start a background loop to update metrics
		go func() {
			for {
				sockets, _ := monitor.GetTCPConnections()
				report := monitor.AnalyzeConnections(sockets)

				exporter.UpdateMetric("tcp_connections_total", float64(report.TotalConnections))
				for state, count := range report.ByState {
					exporter.UpdateMetric(fmt.Sprintf("tcp_state_%s", strings.ToLower(string(state))), float64(count))
				}
				// Sleep for 10s
				select {
				case <-cmd.Context().Done():
					return
				default:
					// time.Sleep is fine here
				}
			}
		}()

		return exporter.StartExporter(exportAddr)
	},
}

func init() {
	rootCmd.AddCommand(monitorCmd)
	monitorCmd.AddCommand(connCmd)
	monitorCmd.AddCommand(backlogCmd)
	monitorCmd.AddCommand(thunderingCmd)
	monitorCmd.AddCommand(serveCmd)

	thunderingCmd.Flags().IntVar(&herdThreshold, "threshold", 100, "SYN_RECV threshold for thundering herd detection")
	serveCmd.Flags().StringVar(&exportAddr, "addr", ":9090", "Address to serve metrics on")
}
