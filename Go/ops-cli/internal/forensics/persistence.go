package forensics

import (
	"bufio"
	"context"
	"os"
	"path/filepath"
	"strings"
)

// PersistenceIncident represents a suspicious find in a profile/bashrc file
type PersistenceIncident struct {
	Path        string `json:"path"`
	AnomalyType string `json:"anomaly_type"`
	LineContent string `json:"line_content"`
}

// AuditShellInitFiles scans common shell initialization files for persistence
func AuditShellInitFiles(ctx context.Context, homeDir string) ([]PersistenceIncident, error) {
	var incidents []PersistenceIncident

	// Common files to check
	filesToCheck := []string{
		"/etc/profile",
		"/etc/bash.bashrc",
		filepath.Join(homeDir, ".bashrc"),
		filepath.Join(homeDir, ".profile"),
		filepath.Join(homeDir, ".bash_profile"),
		filepath.Join(homeDir, ".bash_logout"),
	}

	for _, path := range filesToCheck {
		select {
		case <-ctx.Done():
			return incidents, ctx.Err()
		default:
		}

		if _, err := os.Stat(path); os.IsNotExist(err) {
			continue
		}

		fileIncidents, err := auditFile(path)
		if err != nil {
			continue // Log elsewhere
		}
		incidents = append(incidents, fileIncidents...)
	}

	// Add cronjob audit
	cronIncidents, err := AuditCronjobs(ctx)
	if err == nil {
		incidents = append(incidents, cronIncidents...)
	}

	return incidents, nil
}

// AuditCronjobs scans system and user cronjobs for anomalies
func AuditCronjobs(ctx context.Context) ([]PersistenceIncident, error) {
	var incidents []PersistenceIncident

	// System cron files
	systemCronPaths := []string{
		"/etc/crontab",
	}

	// System cron directories
	systemCronDirs := []string{
		"/etc/cron.d",
		"/etc/cron.daily",
		"/etc/cron.hourly",
		"/etc/cron.monthly",
		"/etc/cron.weekly",
	}

	// User crontabs
	userCronDirs := []string{
		"/var/spool/cron/crontabs",
		"/var/spool/cron",
	}

	for _, path := range systemCronPaths {
		if _, err := os.Stat(path); err == nil {
			fileIncidents, _ := auditCronFile(path)
			incidents = append(incidents, fileIncidents...)
		}
	}

	for _, dir := range systemCronDirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			path := filepath.Join(dir, entry.Name())
			fileIncidents, _ := auditCronFile(path)
			incidents = append(incidents, fileIncidents...)
		}
	}

	for _, dir := range userCronDirs {
		entries, err := os.ReadDir(dir)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			path := filepath.Join(dir, entry.Name())
			fileIncidents, _ := auditCronFile(path)
			incidents = append(incidents, fileIncidents...)
		}
	}

	return incidents, nil
}

func auditCronFile(path string) ([]PersistenceIncident, error) {
	var incidents []PersistenceIncident

	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Suspicious patterns in cron
		if strings.Contains(line, "curl") || strings.Contains(line, "wget") {
			if strings.Contains(line, "| bash") || strings.Contains(line, "| sh") || strings.Contains(line, "http") {
				incidents = append(incidents, PersistenceIncident{
					Path:        path,
					AnomalyType: "Cron: Remote Script/Download",
					LineContent: line,
				})
			}
		}

		if strings.Contains(line, "/tmp") || strings.Contains(line, "/dev/shm") || strings.Contains(line, "/. ") {
			incidents = append(incidents, PersistenceIncident{
				Path:        path,
				AnomalyType: "Cron: Suspicious execution path",
				LineContent: line,
			})
		}

		if strings.Contains(line, "base64") || strings.Contains(line, "python -c") || strings.Contains(line, "perl -e") || strings.Contains(line, "php -r") {
			incidents = append(incidents, PersistenceIncident{
				Path:        path,
				AnomalyType: "Cron: Encoded/Inline payload",
				LineContent: line,
			})
		}
	}

	return incidents, nil
}

func auditFile(path string) ([]PersistenceIncident, error) {
	var incidents []PersistenceIncident

	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// 1. Check for command hijacking (aliases)
		if strings.HasPrefix(line, "alias ") {
			parts := strings.SplitN(line, "=", 2)
			if len(parts) > 0 {
				aliasName := strings.TrimPrefix(parts[0], "alias ")
				commonCommands := []string{"ls", "cd", "sudo", "cat", "cp", "mv", "rm", "ssh", "curl", "wget"}
				for _, cmd := range commonCommands {
					if aliasName == cmd {
						incidents = append(incidents, PersistenceIncident{
							Path:        path,
							AnomalyType: "Command Hijack (Alias)",
							LineContent: line,
						})
					}
				}
			}
		}

		// 2. Check for remote script execution
		if strings.Contains(line, "curl") || strings.Contains(line, "wget") {
			if strings.Contains(line, "| bash") || strings.Contains(line, "| sh") {
				incidents = append(incidents, PersistenceIncident{
					Path:        path,
					AnomalyType: "Remote Script Execution",
					LineContent: line,
				})
			}
		}

		// 3. Check for hidden paths
		if strings.Contains(line, "/. ") || strings.Contains(line, "/.hidden") || strings.Contains(line, "/dev/shm") {
			incidents = append(incidents, PersistenceIncident{
				Path:        path,
				AnomalyType: "Hidden path/memory execution",
				LineContent: line,
			})
		}
		
		// 4. Check for background persistence
		if strings.HasSuffix(line, "&") && !strings.Contains(line, "disown") {
			// This can be noisy, but often used for reverse shells
			incidents = append(incidents, PersistenceIncident{
				Path:        path,
				AnomalyType: "Background Persistence",
				LineContent: line,
			})
		}
	}

	return incidents, nil
}
