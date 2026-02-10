package cmd

import (
	"container/heap"
	"context"
	"fmt"
	"io/fs"
	"log/slog"
	"path/filepath"
	"time"

	"github.com/spf13/cobra"
)

// FileEntry represents a file or directory with its size
type FileEntry struct {
	Path string
	Size int64
}

// FileHeap implements heap.Interface for a min-heap of FileEntries based on Size
type FileHeap []FileEntry

func (h FileHeap) Len() int           { return len(h) }
func (h FileHeap) Less(i, j int) bool { return h[i].Size < h[j].Size } // Min-heap to keep smallest of the largest at top
func (h FileHeap) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }

func (h *FileHeap) Push(x interface{}) {
	*h = append(*h, x.(FileEntry))
}

func (h *FileHeap) Pop() interface{} {
	old := *h
	n := len(old)
	x := old[n-1]
	*h = old[0 : n-1]
	return x
}

var diskCmd = &cobra.Command{
	Use:   "disk",
	Short: "Analyze disk usage",
	Long:  `Identify top disk-consuming directories and large files.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		start := time.Now()
		ctx := cmd.Context()

		targetDirs := []string{"/"} // Default to root if no args
		if len(args) > 0 {
			targetDirs = args
		}

		slog.Info("Starting disk analysis", "targets", targetDirs)

		// 7. Resource Constraints: Use a Min-Heap to track only top K items
		// We want the TOP 5 largest files.
		// Maintain a min-heap of size 5. If a new file is larger than the minimum (root),
		// replace root.
		topFiles := &FileHeap{}
		heap.Init(topFiles)
		const maxItems = 5

		// For directories, we still need aggregation. To respect memory constraints,
		// we could implement a depth-limited walk or just aggregate direct children.
		// For this implementation, we will track directories but use a map.
		// Optimization: Only track directories > 100MB to save memory if needed.
		dirSizes := make(map[string]int64)

		for _, root := range targetDirs {
			err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
				// 4. Context for Everything: Check for cancellation
				select {
				case <-ctx.Done():
					return ctx.Err()
				default:
				}

				// 2. Never Ignore an error
				if err != nil {
					slog.Warn("Failed to access path", "path", path, "error", err)
					return nil // Skip this file/dir but continue walking
				}

				info, err := d.Info()
				if err != nil {
					return nil
				}

				size := info.Size()

				if !d.IsDir() {
					// File Logic: Maintain Top K Heap
					if topFiles.Len() < maxItems {
						heap.Push(topFiles, FileEntry{Path: path, Size: size})
					} else if size > (*topFiles)[0].Size {
						heap.Pop(topFiles)
						heap.Push(topFiles, FileEntry{Path: path, Size: size})
					}

					// Directory Logic: Aggregate size to parent directory (simplistic non-recursive for now)
					dir := filepath.Dir(path)
					dirSizes[dir] += size
				}
				return nil
			})

			if err != nil {
				if err == context.Canceled || err == context.DeadlineExceeded {
					return fmt.Errorf("disk analysis cancelled: %w", err)
				}
				slog.Error("Error walking directory", "root", root, "error", err)
				// Don't fully fail, continue to next root if any
			}
		}

		// Convert Heap to Slice and Sort (Descending) for display
		sortedFiles := make([]FileEntry, 0, topFiles.Len())
		for topFiles.Len() > 0 {
			sortedFiles = append(sortedFiles, heap.Pop(topFiles).(FileEntry))
		}
		// Heap pops smallest first, so reverse to get largest first
		for i, j := 0, len(sortedFiles)-1; i < j; i, j = i+1, j-1 {
			sortedFiles[i], sortedFiles[j] = sortedFiles[j], sortedFiles[i]
		}

		fmt.Println("\nTop 5 Largest Files:")
		for _, file := range sortedFiles {
			fmt.Printf("%.2f MB\t%s\n", float64(file.Size)/(1024*1024), file.Path)
		}

		// Process Top Directories from Map
		// (For a real system tool, we might use a similar heap approach during iteration if map gets too big)
		topDirs := &FileHeap{}
		heap.Init(topDirs)

		for path, size := range dirSizes {
			if topDirs.Len() < maxItems {
				heap.Push(topDirs, FileEntry{Path: path, Size: size})
			} else if size > (*topDirs)[0].Size {
				heap.Pop(topDirs)
				heap.Push(topDirs, FileEntry{Path: path, Size: size})
			}
		}

		sortedDirs := make([]FileEntry, 0, topDirs.Len())
		for topDirs.Len() > 0 {
			sortedDirs = append(sortedDirs, heap.Pop(topDirs).(FileEntry))
		}
		for i, j := 0, len(sortedDirs)-1; i < j; i, j = i+1, j-1 {
			sortedDirs[i], sortedDirs[j] = sortedDirs[j], sortedDirs[i]
		}

		fmt.Println("\nTop 5 Largest Directories (Direct Content):")
		for _, dir := range sortedDirs {
			fmt.Printf("%.2f MB\t%s\n", float64(dir.Size)/(1024*1024), dir.Path)
		}

		elapsed := time.Since(start)
		slog.Info("Disk analysis complete", "duration", elapsed.String())
		return nil
	},
}

func init() {
	rootCmd.AddCommand(diskCmd)
}
