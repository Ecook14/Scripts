package forensics

import (
	"context"
	"io/fs"
	"log/slog"
	"path/filepath"
	"time"
)

// FileEvent represents a file system event in the timeline
type FileEvent struct {
	Path      string
	ModTime   time.Time
	Size      int64
	IsDir     bool
}

// Timeline generates a list of files modified within the last 'since' duration
func Timeline(ctx context.Context, root string, since time.Duration) ([]FileEvent, error) {
	var events []FileEvent
	threshold := time.Now().Add(-since)

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			slog.Warn("Failed to access path", "path", path, "error", err)
			return nil
		}
		
		info, err := d.Info()
		if err != nil {
			return nil
		}

		if info.ModTime().After(threshold) {
			events = append(events, FileEvent{
				Path:    path,
				ModTime: info.ModTime(),
				Size:    info.Size(),
				IsDir:   d.IsDir(),
			})
		}
		
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		return nil
	})

	return events, err
}
