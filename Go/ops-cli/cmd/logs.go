package cmd

import (
	"fmt"
	"log/slog"
	"ops-cli/internal/logs"

	"github.com/spf13/cobra"
)

var (
	query    string
	logLimit int
)

// logsCmd represents the logs command
var logsCmd = &cobra.Command{
	Use:   "logs",
	Short: "Unified log analysis and searching",
	Long:  `Search across Apache, Exim, MySQL, and System logs using a high-performance interface.`,
}

var apacheLogCmd = &cobra.Command{
	Use:   "apache",
	Short: "Search Apache error logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runLogSearch(cmd, logs.TypeApache)
	},
}

var eximLogCmd = &cobra.Command{
	Use:   "exim",
	Short: "Search Exim main logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runLogSearch(cmd, logs.TypeExim)
	},
}

var mysqlLogCmd = &cobra.Command{
	Use:   "mysql",
	Short: "Search MySQL error logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runLogSearch(cmd, logs.TypeMySQL)
	},
}

var systemLogCmd = &cobra.Command{
	Use:   "system",
	Short: "Search System (syslog/messages) logs",
	RunE: func(cmd *cobra.Command, args []string) error {
		return runLogSearch(cmd, logs.TypeSystem)
	},
}

func runLogSearch(cmd *cobra.Command, ltype logs.LogType) error {
	ctx := cmd.Context()
	if query == "" {
		return fmt.Errorf("search query required via --query flag")
	}

	results, err := logs.Search(ctx, ltype, query, logLimit)
	if err != nil {
		return fmt.Errorf("search failed: %w", err)
	}

	if len(results) == 0 {
		slog.Info("No matches found", "type", ltype, "query", query)
		return nil
	}

	slog.Info("Search Complete", "matches", len(results))
	for _, res := range results {
		fmt.Printf("[%s:%d] %s\n", res.Path, res.Line, res.Content)
	}

	return nil
}

func init() {
	rootCmd.AddCommand(logsCmd)
	logsCmd.AddCommand(apacheLogCmd)
	logsCmd.AddCommand(eximLogCmd)
	logsCmd.AddCommand(mysqlLogCmd)
	logsCmd.AddCommand(systemLogCmd)

	logsCmd.PersistentFlags().StringVarP(&query, "query", "q", "", "Search string")
	logsCmd.PersistentFlags().IntVarP(&logLimit, "limit", "l", 50, "Limit number of results")
}
