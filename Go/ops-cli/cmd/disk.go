package cmd

import (
	"fmt"
	"log/slog"
	"ops-cli/internal/disk"

	"github.com/spf13/cobra"
)

var (
	diskTopK    int
	diskMinSize int64
)

var diskCmd = &cobra.Command{
	Use:   "disk [paths...]",
	Short: "Analyze disk usage",
	Long:  `Identify top disk-consuming directories and large files.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()

		targets := []string{"."}
		if len(args) > 0 {
			targets = args
		}

		slog.Info("Starting disk analysis", "targets", targets, "top", diskTopK, "min_size_mb", diskMinSize)

		report, err := disk.Analyze(ctx, targets, disk.Options{
			TopK:    diskTopK,
			MinSize: diskMinSize * 1024 * 1024, // Convert MB to bytes
		})

		if err != nil {
			return fmt.Errorf("analysis failed: %w", err)
		}

		if jsonOutput {
			render(report, "")
			return nil
		}

		fmt.Printf("\nTop %d Largest Files:\n", diskTopK)
		for _, file := range report.TopFiles {
			fmt.Printf("%.2f MB\t%s\n", float64(file.Size)/(1024*1024), file.Path)
		}

		fmt.Printf("\nTop %d Largest Directories (Direct Content):\n", diskTopK)
		for _, dir := range report.TopDirs {
			fmt.Printf("%.2f MB\t%s\n", float64(dir.Size)/(1024*1024), dir.Path)
		}

		return nil
	},
}

func init() {
	rootCmd.AddCommand(diskCmd)
	diskCmd.Flags().IntVarP(&diskTopK, "top", "n", 5, "Number of top items to show")
	diskCmd.Flags().Int64Var(&diskMinSize, "min-size", 1, "Minimum file size to report (in MB)")
}
