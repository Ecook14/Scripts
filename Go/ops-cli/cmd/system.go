package cmd

import (
	"bufio"
	"fmt"
	"log/slog"
	"os"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var systemCmd = &cobra.Command{
	Use:   "system",
	Short: "Diagnostics for system health",
	Long:  `Provides real-time information about CPU, memory, and load averages`,
	RunE: func(cmd *cobra.Command, args []string) error {
		memTotal, memFree, err := getSystemMemory()

		if jsonOutput {
			report := map[string]interface{}{
				"os":        runtime.GOOS,
				"arch":      runtime.GOARCH,
				"cpus":      runtime.NumCPU(),
				"mem_total": memTotal,
				"mem_free":  memFree,
			}
			if runtime.GOOS == "linux" {
				load, _ := os.ReadFile("/proc/loadavg")
				report["load"] = strings.TrimSpace(string(load))
			}
			render(report, "")
			return nil
		}

		fmt.Printf("System Health Report at %s\n", time.Now().Format(time.RFC1123))
		fmt.Println("----------------------------------------")
		
		fmt.Printf("OS: %s/%s\n", runtime.GOOS, runtime.GOARCH)
		fmt.Printf("CPUs: %d\n", runtime.NumCPU())
		
		// 1. Zero-Dependency Minimalism: Parse /proc files directly on Linux
		if runtime.GOOS == "linux" {
			load, err := os.ReadFile("/proc/loadavg")
			if err == nil {
				fmt.Printf("Load Average: %s", string(load))
			} else {
				slog.Warn("Could not read loadavg", "error", err)
			}
		} else {
			fmt.Println("Load Average: N/A (Windows/Mac requires syscalls or deps)")
		}

		if err != nil {
			slog.Warn("Could not read memory info", "error", err)
		} else {
			fmt.Printf("Memory: Used %.2f GB / Total %.2f GB\n", 
				float64(memTotal-memFree)/(1024*1024*1024), 
				float64(memTotal)/(1024*1024*1024))
		}
		
		fmt.Println("----------------------------------------")
		return nil
	},
}

// getSystemMemory returns total and free memory in bytes
// It parses /proc/meminfo on Linux, and falls back to runtime stats on others
func getSystemMemory() (int64, int64, error) {
	if runtime.GOOS == "linux" {
		file, err := os.Open("/proc/meminfo")
		if err != nil {
			return 0, 0, err
		}
		defer file.Close()

		var total, free int64
		scanner := bufio.NewScanner(file)
		for scanner.Scan() {
			line := scanner.Text()
			fields := strings.Fields(line)
			if len(fields) < 2 {
				continue
			}
			
			key := strings.TrimSuffix(fields[0], ":")
			val, err := strconv.ParseInt(fields[1], 10, 64)
			if err != nil {
				continue
			}
			// /proc/meminfo values are in kB
			valBytes := val * 1024

			switch key {
			case "MemTotal":
				total = valBytes
			case "MemAvailable": // Preferred over MemFree
				free = valBytes
			case "MemFree":
				if free == 0 { // Fallback if MemAvailable missing
					free = valBytes
				}
			}
		}
		return total, free, scanner.Err()
	}

	// Fallback for Windows/Mac (using Go GC stats as proxy is inaccurate for System RAM, 
	// but strictly adhering to "No 3rd party deps" limits us here without CGO/Syscalls)
	// For "senior admin" scripts, we'd typically cross-compile or use syscall package, 
	// but for this snippet we'll return a stub or use runtime constraints.
	// Returning 0 to indicate "not available" is safer than lying.
	return 0, 0, fmt.Errorf("memory stats not implemented for %s without cgo/syscall", runtime.GOOS)
}

func init() {
	rootCmd.AddCommand(systemCmd)
}
