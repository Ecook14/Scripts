package incident

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"
)

// OOMCheck scans system logs for kernel Out-Of-Memory events
type OOMCheck struct {
	LogPath string // e.g. /var/log/syslog or /var/log/messages
}

func (c *OOMCheck) Name() string {
	return "OOM Killer Audit"
}

func (c *OOMCheck) Run(ctx context.Context) ([]Incident, error) {
	paths := []string{c.LogPath, "/var/log/syslog", "/var/log/messages", "/var/log/kern.log"}
	
	var incidents []Incident
	for _, path := range paths {
		if path == "" {
			continue
		}
		
		f, err := os.Open(path)
		if err != nil {
			continue
		}
		defer f.Close()

		// Scan last 1000 lines for "Out of memory" or "Killed process"
		// For simplicity, we scan the whole file but looking for recent events
		scanner := bufio.NewScanner(f)
		for scanner.Scan() {
			line := scanner.Text()
			if strings.Contains(line, "Out of memory") || strings.Contains(line, "invoked oom-killer") {
				incidents = append(incidents, Incident{
					CheckName:   c.Name(),
					Description: fmt.Sprintf("OOM Event Detected in %s: %s", path, line),
				})
			}
		}
		// Break after first successful log read to avoid duplicates across syslog/kern.log
		if len(incidents) > 0 {
			break
		}
	}

	return incidents, nil
}

// KillerProcessCheck looks for overzealous killer daemons or scripts
type KillerProcessCheck struct{}

func (c *KillerProcessCheck) Name() string {
	return "Process Terminator Detection"
}

func (c *KillerProcessCheck) Run(ctx context.Context) ([]Incident, error) {
	// Identify processes that might be killing others
	// Examples: systemd-oomd, earlyoom, or custom "nanny" scripts
	
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return nil, nil
	}

	killerNames := []string{"oomd", "earlyoom", "monit", "watchdog"}
	
	var incidents []Incident
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		// Read comm (process name)
		commPath := fmt.Sprintf("/proc/%s/comm", entry.Name())
		data, err := os.ReadFile(commPath)
		if err != nil {
			continue
		}

		name := strings.TrimSpace(string(data))
		for _, kname := range killerNames {
			if strings.Contains(strings.ToLower(name), kname) {
				incidents = append(incidents, Incident{
					CheckName:   c.Name(),
					Description: fmt.Sprintf("Active system 'killer' daemon detected: %s (PID %s). This service may be automatically terminating your commands.", name, entry.Name()),
				})
			}
		}
	}

	return incidents, nil
}
