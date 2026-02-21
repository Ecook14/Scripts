package cmd

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"time"

	"ops-cli/internal/forensics"

	"github.com/spf13/cobra"
)

var (
	targetPath     string
	timeSince      string
	quarantinePath string
	restoreFile    string
	restoreAll     bool
)

// forensicsCmd represents the forensics command
var forensicsCmd = &cobra.Command{
	Use:   "forensics",
	Short: "Digital forensics and malware mitigation",
	Long:  `Forensic Malware Mitigation Suite (Project 2).`,
}

var scanCmd = &cobra.Command{
	Use:   "scan",
	Short: "Scan for malware signatures",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		if ctx == nil {
			ctx = context.Background()
		}

		if targetPath == "" {
			return fmt.Errorf("target path is required")
		}

		slog.Info("Starting Forensic Scan", "path", targetPath)

		scanner := &forensics.Scanner{
			Root:       targetPath,
			Signatures: forensics.DefaultSignatures(),
			Workers:    8, // Parallel scanning
		}

		results, err := scanner.Scan(ctx)
		if err != nil {
			return fmt.Errorf("scan failed: %w", err)
		}

		if jsonOutput {
			render(results, "")
			return nil
		}

		if len(results) == 0 {
			slog.Info("Clean! No malware signatures found.")
			return nil
		}

		slog.Warn("Potential Malware Detected", "count", len(results))
		for _, r := range results {
			fmt.Printf("[MALWARE] %s (Signature: %s)\n", r.Path, r.Signature)
			
			// 3. Immutable Check (Advanced)
			// Rondo/Polymorphic malware uses chattr +i to persist.
			isImmutable, err := forensics.IsImmutable(r.Path)
			if err != nil {
				slog.Error("Failed to check file attributes", "path", r.Path, "error", err)
			}
			if isImmutable {
				slog.Warn("FILE IS IMMUTABLE (+i) - ATTEMPTING UNLOCK", "path", r.Path)
				if err := forensics.MakeMutable(ctx, r.Path); err != nil {
					slog.Error("Failed to unlock file", "error", err)
				} else {
					slog.Info("Successfully unlocked file (chattr -i)", "path", r.Path)
				}
			}

			if quarantinePath != "" {
				slog.Info("Quarantining malicious file", "path", r.Path)
				dest, err := forensics.Quarantine(ctx, r.Path, quarantinePath)
				if err != nil {
					slog.Error("Quarantine failed", "path", r.Path, "error", err)
				} else {
					slog.Info("File isolated successfully", "original", r.Path, "quarantine", dest)
				}
			}
		}
		
		// Exit with code 1 if malware found (for CI/CD)
		if len(results) > 0 {
			os.Exit(1)
		}
		return nil
	},
}

var timelineCmd = &cobra.Command{
	Use:   "timeline",
	Short: "Analyze file modification timeline",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		if ctx == nil {
			ctx = context.Background()
		}

		if targetPath == "" {
			return fmt.Errorf("target path is required")
		}

		duration, err := time.ParseDuration(timeSince)
		if err != nil {
			return fmt.Errorf("invalid duration format (e.g. 24h): %w", err)
		}

		slog.Info("Generating Timeline", "path", targetPath, "since", timeSince)

		events, err := forensics.Timeline(ctx, targetPath, duration)
		if err != nil {
			return fmt.Errorf("timeline analysis failed: %w", err)
		}

		if jsonOutput {
			render(events, "")
			return nil
		}

		if len(events) == 0 {
			slog.Info("No file modifications found in the specified window.")
			return nil
		}

		fmt.Printf("Displaying %d file events in the last %s:\n", len(events), timeSince)
		for _, e := range events {
			fmt.Printf("[%s] %s (%d bytes)\n", e.ModTime.Format(time.RFC3339), e.Path, e.Size)
		}
		return nil
	},
}

var persistenceCmd = &cobra.Command{
	Use:   "persistence",
	Short: "Audit shell initialization files for persistence anomalies",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		home, _ := os.UserHomeDir()

		slog.Info("Starting persistence audit", "home", home)
		incidents, err := forensics.AuditShellInitFiles(ctx, home)
		if err != nil {
			return fmt.Errorf("audit failed: %w", err)
		}

		if jsonOutput {
			render(incidents, "")
			return nil
		}

		if len(incidents) == 0 {
			slog.Info("No persistence anomalies detected in shell init files.")
			return nil
		}

		slog.Warn("Persistence Anomalies Detected", "count", len(incidents))
		for _, inc := range incidents {
			fmt.Printf("[%s] %s: %s\n", inc.AnomalyType, inc.Path, inc.LineContent)
		}

		if len(incidents) > 0 {
			os.Exit(1)
		}
		return nil
	},
}

var restoreCmd = &cobra.Command{
	Use:   "restore",
	Short: "Restore files from quarantine",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()

		if restoreAll {
			if quarantinePath == "" {
				return fmt.Errorf("--quarantine directory path is required for bulk restore")
			}
			slog.Info("Restoring all files from quarantine", "dir", quarantinePath)
			count, err := forensics.RestoreAll(ctx, quarantinePath)
			if err != nil {
				return err
			}
			slog.Info("Restoration complete", "count", count)
			return nil
		}

		if restoreFile == "" {
			return fmt.Errorf("either --file or --all must be specified")
		}

		slog.Info("Restoring file from quarantine", "path", restoreFile)
		if err := forensics.Restore(ctx, restoreFile); err != nil {
			return fmt.Errorf("restore failed: %w", err)
		}

		slog.Info("File restored successfully", "path", restoreFile)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(forensicsCmd)
	forensicsCmd.AddCommand(scanCmd)
	forensicsCmd.AddCommand(timelineCmd)
	forensicsCmd.AddCommand(persistenceCmd)
	forensicsCmd.AddCommand(restoreCmd)

	forensicsCmd.PersistentFlags().StringVarP(&targetPath, "path", "p", ".", "Target directory to analyze")
	scanCmd.Flags().StringVar(&quarantinePath, "quarantine", "", "Move malicious files to this directory")
	timelineCmd.Flags().StringVarP(&timeSince, "since", "t", "24h", "Time window (e.g. 24h, 2h, 30m)")

	restoreCmd.Flags().StringVar(&restoreFile, "file", "", "Specific .quarantine file to restore")
	restoreCmd.Flags().BoolVar(&restoreAll, "all", false, "Restore all files in the quarantine directory")
	restoreCmd.Flags().StringVar(&quarantinePath, "quarantine", "", "Directory where quarantined files are stored")
}
