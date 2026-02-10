package cmd

import (
	"bufio"
	"context"
	"fmt"
	"log/slog"
	"os"
	"sort"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var emailCmd = &cobra.Command{
	Use:   "email",
	Short: "Analyze Exim mail logs (ec.pl replacement)",
	Long:  `Parses Exim logs to count emails and identify top senders.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		logPath := "/var/log/exim_mainlog"
		
		// Flag parsing could be added here (e.g. --file)

		slog.Info("Analyzing email headers...", "file", logPath)
		start := time.Now()

		stats, err := parseEximLog(ctx, logPath)
		if err != nil {
			return fmt.Errorf("failed to parse logs: %w", err)
		}

		printEmailStats(stats)
		
		slog.Info("Analysis complete", "duration", time.Since(start))
		return nil
	},
}

type EmailStats struct {
	TotalEmails int
	Senders     map[string]int
}

func parseEximLog(ctx context.Context, path string) (*EmailStats, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()

	stats := &EmailStats{
		Senders: make(map[string]int),
	}

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		// 4. Context Check
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		default:
		}

		line := scanner.Text()
		
		// Logic: Identify lines with "<=" which indicate message arrival (sender)
		// 2024-02-10 12:00:00 1xxxxx-xxxx-xx <= sender@example.com H=...
		if strings.Contains(line, "<=") {
			parts := strings.Fields(line)
			sender := "unknown"
			
			// Simple heuristic parsing (ec.pl uses regex, Go plain string split is faster/simpler if format is consistent)
			// Iterate to find "<=" and take the next field?
			for i, part := range parts {
				if part == "<=" && i+1 < len(parts) {
					sender = parts[i+1]
					break
				}
			}
			
			stats.TotalEmails++
			stats.Senders[sender]++
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}

	return stats, nil
}

func printEmailStats(stats *EmailStats) {
	fmt.Println("\nEmail Traffic Summary")
	fmt.Println("---------------------")
	fmt.Printf("Total Emails Processed: %d\n", stats.TotalEmails)
	
	fmt.Println("\nTop 10 Senders:")
	
	type kv struct {
		Key   string
		Value int
	}
	
	var ss []kv
	for k, v := range stats.Senders {
		ss = append(ss, kv{k, v})
	}
	
	sort.Slice(ss, func(i, j int) bool {
		return ss[i].Value > ss[j].Value
	})
	
	count := 0
	for _, kv := range ss {
		fmt.Printf("%5d %s\n", kv.Value, kv.Key)
		count++
		if count >= 10 {
			break
		}
	}
}

func init() {
	rootCmd.AddCommand(emailCmd)
}
