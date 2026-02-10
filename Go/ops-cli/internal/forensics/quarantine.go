package forensics

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// QuarantineMetadata stores info needed to revert a quarantine
type QuarantineMetadata struct {
	OriginalPath string      `json:"original_path"`
	QuarantinedAt time.Time   `json:"quarantined_at"`
	OriginalMode os.FileMode `json:"original_mode"`
}

// Quarantine isolates a file and saves restoration metadata
func Quarantine(ctx context.Context, src string, quarantineDir string) (string, error) {
	if _, err := os.Stat(quarantineDir); os.IsNotExist(err) {
		if err := os.MkdirAll(quarantineDir, 0700); err != nil {
			return "", fmt.Errorf("failed to create quarantine dir: %w", err)
		}
	}

	info, err := os.Stat(src)
	if err != nil {
		return "", fmt.Errorf("failed to stat source: %w", err)
	}

	// Make sure file is mutable before moving
	_ = MakeMutable(ctx, src)

	timestamp := time.Now().Unix()
	dest := filepath.Join(quarantineDir, fmt.Sprintf("%d_%s.quarantine", timestamp, filepath.Base(src)))
	metaPath := dest + ".json"

	// Save metadata
	meta := QuarantineMetadata{
		OriginalPath:  src,
		QuarantinedAt: time.Now(),
		OriginalMode:  info.Mode(),
	}
	metaBytes, _ := json.MarshalIndent(meta, "", "  ")
	if err := os.WriteFile(metaPath, metaBytes, 0600); err != nil {
		return "", fmt.Errorf("failed to save metadata: %w", err)
	}

	// Strip all permissions from source first (defensive)
	_ = os.Chmod(src, 0000)

	// Move file
	if err := os.Rename(src, dest); err != nil {
		_ = os.Remove(metaPath) // Cleanup meta if move fails
		return "", fmt.Errorf("failed to move file to quarantine: %w", err)
	}

	return dest, nil
}

// Restore moves a quarantined file back to its original location
func Restore(ctx context.Context, quarantinedPath string) error {
	metaPath := quarantinedPath + ".json"
	metaBytes, err := os.ReadFile(metaPath)
	if err != nil {
		return fmt.Errorf("could not find metadata for %s: %w", quarantinedPath, err)
	}

	var meta QuarantineMetadata
	if err := json.Unmarshal(metaBytes, &meta); err != nil {
		return fmt.Errorf("failed to parse metadata: %w", err)
	}

	// Ensure parent dir exists
	parent := filepath.Dir(meta.OriginalPath)
	if err := os.MkdirAll(parent, 0755); err != nil {
		return fmt.Errorf("failed to ensure original directory exists: %w", err)
	}

	// Move back
	if err := os.Rename(quarantinedPath, meta.OriginalPath); err != nil {
		return fmt.Errorf("failed to restore file: %w", err)
	}

	// Restore permissions
	_ = os.Chmod(meta.OriginalPath, meta.OriginalMode)

	// Cleanup meta
	_ = os.Remove(metaPath)

	return nil
}

// RestoreAll restores every file in the quarantine directory
func RestoreAll(ctx context.Context, quarantineDir string) (int, error) {
	entries, err := os.ReadDir(quarantineDir)
	if err != nil {
		return 0, err
	}

	restored := 0
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".quarantine") {
			continue
		}

		path := filepath.Join(quarantineDir, entry.Name())
		if err := Restore(ctx, path); err == nil {
			restored++
		}
	}
	return restored, nil
}
