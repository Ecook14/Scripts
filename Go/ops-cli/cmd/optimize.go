package cmd

import (
	"fmt"
	"log/slog"
	"math"

	"github.com/spf13/cobra"
)

var optimizeCmd = &cobra.Command{
	Use:   "optimize",
	Short: "Optimize system performance",
	Long:  `Calculates optimal settings for Apache and MySQL based on available RAM.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		fmt.Println("Optimization Recommendations:")
		fmt.Println("------------------------------")
		
		// 1. Zero-Dependency Minimalism: Use shared /proc parser
		memTotal, _, err := getSystemMemory()
		var totalRamMB float64
		
		if err != nil {
			slog.Warn("Could not detect system memory, defaulting to 4GB", "error", err)
			totalRamMB = 4096.0
		} else {
			totalRamMB = float64(memTotal) / (1024 * 1024)
			fmt.Printf("Detected System Memory: %.0f MB\n", totalRamMB)
		}

		apacheMaxClients := calculateApacheMaxClients(totalRamMB)
		fmt.Printf("[Apache] Recommended MaxRequestWorkers: %d\n", apacheMaxClients)

		mysqlBufferPool := calculateMySQLBufferPool(totalRamMB)
		fmt.Printf("[MySQL] Recommended innodb_buffer_pool_size: %s\n", mysqlBufferPool)
		
		fmt.Println("\nTo apply these changes, utilize configuration management tools or edit configs manually.")
		return nil
	},
}

func calculateApacheMaxClients(ramMB float64) int {
	// Logic from optimize.sh:
	// Mem for non-apache: 2048MB
	// Avg Apache Process: ~60MB (conservative estimate if not measured)
	nonApacheMem := 2048.0
	availableForApache := ramMB - nonApacheMem
	if availableForApache < 0 {
		return 10 // Minimum safe value
	}
	avgProcessSize := 60.0 
	return int(math.Floor(availableForApache / avgProcessSize))
}

func calculateMySQLBufferPool(ramMB float64) string {
	if ramMB < 2048 {
		return "256M"
	}
	return "512M" // As per script logic, but modern standards suggest significantly more (50-70% of RAM dedicated to DB)
}


func init() {
	rootCmd.AddCommand(optimizeCmd)
}
