package cmd

import (
	"archive/zip"
	"bufio"
	"context"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/spf13/cobra"
)

var securityCmd = &cobra.Command{
	Use:   "security",
	Short: "Security auditing and hardening",
	Long:  `Provides mechanisms for server hardening and abuse investigation.`,
}

var hardenCmd = &cobra.Command{
	Use:   "harden",
	Short: "Check system hardening status",
	RunE: func(cmd *cobra.Command, args []string) error {
		slog.Info("Running Hardening Scan...")
		ctx := cmd.Context()

		checks := []struct {
			name    string
			file    string
			pattern string
			expect  bool // true if pattern should exist, false if it should NOT exist (or exist with "no")
		}{
			{"SSH Root Login", "/etc/ssh/sshd_config", "PermitRootLogin no", true},
			{"FTP Anonymous", "/etc/pure-ftpd/pure-ftpd.conf", "NoAnonymous yes", true},
		}

		for _, check := range checks {
			// 4. Context for Everything: Check cancellation
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			found, err := checkConfig(check.file, check.pattern)
			if err != nil {
				slog.Warn("Could not check config", "check", check.name, "file", check.file, "error", err)
				continue
			}

			status := "FAIL"
			if found == check.expect {
				status = "PASS"
			}
			fmt.Printf("[%s] %s: %s\n", status, check.name, check.file)
		}

		return nil
	},
}

var abuseCmd = &cobra.Command{
	Use:   "abuse [DOMAIN]",
	Short: "Package abuse evidence for a domain",
	Args:  cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		domain := args[0]
		ctx := cmd.Context()
		slog.Info("Collecting abuse evidence", "domain", domain)

		logDirs := []string{
			"/var/log/messages",
			"/var/log/exim_mainlog",
			fmt.Sprintf("/var/log/apache2/domlogs/%s", domain),
		}

		outputZip := fmt.Sprintf("%s_abuse_%d.zip", domain, time.Now().Unix())
		
		// 1. Zero-Dependency Minimalism: Use archive/zip
		if err := createZip(ctx, outputZip, logDirs); err != nil {
			return fmt.Errorf("failed to create abuse package: %w", err)
		}

		slog.Info("Abuse package created successfully", "file", outputZip)
		return nil
	},
}

// checkConfig reads a file and checks if it contains a pattern (Go native implementation)
func checkConfig(path, pattern string) (bool, error) {
	file, err := os.Open(path)
	if err != nil {
		return false, err
	}
	defer file.Close()

	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if strings.HasPrefix(line, "#") {
			continue // Skip comments
		}
		if strings.Contains(line, pattern) {
			return true, nil
		}
	}
	return false, scanner.Err()
}

// createZip creates a zip archive of the specified files
func createZip(ctx context.Context, output string, files []string) error {
	zipFile, err := os.Create(output)
	if err != nil {
		return err
	}
	// 3. Graceful Signal Handling: Ensure file is closed even on panic/error
	defer zipFile.Close()

	archive := zip.NewWriter(zipFile)
	defer archive.Close()

	for _, filePath := range files {
		// 4. Context for Everything
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}

		info, err := os.Stat(filePath)
		if err != nil {
			slog.Warn("Skipping missing file", "file", filePath)
			continue
		}

		header, err := zip.FileInfoHeader(info)
		if err != nil {
			return err
		}
		header.Name = filepath.Base(filePath)
		header.Method = zip.Deflate

		writer, err := archive.CreateHeader(header)
		if err != nil {
			return err
		}

		file, err := os.Open(filePath)
		if err != nil {
			return err
		}
		
		// Use io.Copy for streaming
		_, err = io.Copy(writer, file)
		file.Close()
		if err != nil {
			return err
		}
	}
	return nil
}

func init() {
	securityCmd.AddCommand(hardenCmd)
	securityCmd.AddCommand(abuseCmd)
	rootCmd.AddCommand(securityCmd)
}
