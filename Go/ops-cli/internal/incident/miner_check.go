package incident

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// MinerCheck detects actively running mining processes
type MinerCheck struct {
	// Add strict mode later?
}

func (c *MinerCheck) Name() string {
	return "Active Cryptominer"
}

func (c *MinerCheck) Run(ctx context.Context) ([]Incident, error) {
	// Scan /proc for suspicious cmdlines
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil, fmt.Errorf("failed to scan /proc: %w", err)
	}

	suspiciousArgs := []string{
		"stratum+tcp",
		"xmrig",
		"minerd",
		"cpuminer",
		"nicehash",
		"xmr-stak",
		"cryptonight",
		"nanopool",
		"monero",
	}

	var incidents []Incident

	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		
		pid, err := strconv.Atoi(entry.Name())
		if err != nil {
			continue // Not a PID
		}

		// Read cmdline
		cmdlinePath := filepath.Join("/proc", entry.Name(), "cmdline")
		data, err := os.ReadFile(cmdlinePath)
		if err != nil {
			continue
		}
		
		// cmdline uses null bytes as separators
		args := strings.ReplaceAll(string(data), "\x00", " ")
		
		for _, sig := range suspiciousArgs {
			if strings.Contains(strings.ToLower(args), sig) {
				incidents = append(incidents, Incident{
					CheckName:   c.Name(),
					Description: fmt.Sprintf("suspicious miner process detected (PID %d): %s", pid, args),
					Remediation: &ProcessKill{PID: pid},
				})
				break // Found one signature for this PID, move to next PID
			}
		}
	}

	return incidents, nil
}
