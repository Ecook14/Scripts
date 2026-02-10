package cmd

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"strings"

	"github.com/spf13/cobra"
)

var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "Analyze and tail logs",
	Long: `Consolidated log viewer for Apache, Exim, MySQL, and System logs.
Ported from 'adlog.sh' and 'l2.sh'.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		selectedLog := promptUser("Select Log Type: (apache, exim, mysql, system)")
		ctx := cmd.Context()

		switch selectedLog {
		case "apache":
			return analyzeApacheLogs(ctx)
		case "exim":
			return analyzeEximLogs(ctx)
		case "mysql":
			return analyzeMySQLLogs(ctx)
		case "system":
			return analyzeSystemLogs(ctx)
		default:
			return fmt.Errorf("invalid log type: %s", selectedLog)
		}
	},
}

func promptUser(msg string) string {
	fmt.Print(msg + " > ")
	var input string
	fmt.Scanln(&input)
	return strings.ToLower(strings.TrimSpace(input))
}

func analyzeApacheLogs(ctx context.Context) error {
	domain := promptUser("Enter domain name (or leave empty for global):")
	logFile := "/var/log/apache2/error.log"

	if domain != "" {
		// 6. Defensive Command Execution: Individual args, absolute path
		return executeCommand(ctx, "/usr/bin/grep", domain, logFile)
	}
	return executeTail(ctx, logFile, 50)
}

func analyzeEximLogs(ctx context.Context) error {
	logFile := "/var/log/exim_mainlog"
	slog.Info("Analyzing Exim Logs...")
	term := promptUser("Search term or leave empty to tail:")
	if term != "" {
		return executeCommand(ctx, "/usr/bin/grep", term, logFile)
	}
	return executeTail(ctx, logFile, 50)
}

func analyzeMySQLLogs(ctx context.Context) error {
	logFile := "/var/log/mysqld.log"
	return executeTail(ctx, logFile, 50)
}

func analyzeSystemLogs(ctx context.Context) error {
	logFile := "/var/log/messages"
	term := promptUser("Search term (e.g. error, fail):")
	if term != "" {
		return executeCommand(ctx, "/usr/bin/grep", "-i", term, logFile)
	}
	return executeTail(ctx, logFile, 50)
}

// executeCommand runs a command safely with context cancellation
func executeCommand(ctx context.Context, name string, args ...string) error {
	slog.Info("Executing command", "cmd", name, "args", args)

	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr

	if err := cmd.Run(); err != nil {
		// 2. Never Ignore an error: Wrap and return
		return fmt.Errorf("command execution failed: %w", err)
	}
	return nil
}

func executeTail(ctx context.Context, file string, lines int) error {
	return executeCommand(ctx, "/usr/bin/tail", "-n", fmt.Sprintf("%d", lines), file)
}

func init() {
	rootCmd.AddCommand(logsCmd)
}
