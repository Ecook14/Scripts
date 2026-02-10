package disk

import (
	"container/heap"
	"context"
	"io/fs"
	"path/filepath"
)

// FileEntry represents a file or directory with its size
type FileEntry struct {
	Path string `json:"path"`
	Size int64  `json:"size_bytes"`
}

// FileHeap implements heap.Interface for a min-heap of FileEntries based on Size
type FileHeap []FileEntry

func (h FileHeap) Len() int           { return len(h) }
func (h FileHeap) Less(i, j int) bool { return h[i].Size < h[j].Size }
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

// DiskReport contains the results of a disk analysis
type DiskReport struct {
	TopFiles []FileEntry `json:"top_files"`
	TopDirs  []FileEntry `json:"top_dirs"`
}

// Options configures the disk analysis
type Options struct {
	TopK    int
	MinSize int64
}

// Analyze walks the target directories and finds top disk consumers
func Analyze(ctx context.Context, targets []string, opts Options) (*DiskReport, error) {
	if opts.TopK <= 0 {
		opts.TopK = 5
	}

	topFiles := &FileHeap{}
	heap.Init(topFiles)

	dirSizes := make(map[string]int64)

	for _, root := range targets {
		err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}

			if err != nil {
				return nil // Skip inaccessible
			}

			info, err := d.Info()
			if err != nil {
				return nil
			}

			size := info.Size()

			if !d.IsDir() {
				// Filter by min size
				if size < opts.MinSize {
					return nil
				}

				// Top Files
				if topFiles.Len() < opts.TopK {
					heap.Push(topFiles, FileEntry{Path: path, Size: size})
				} else if size > (*topFiles)[0].Size {
					heap.Pop(topFiles)
					heap.Push(topFiles, FileEntry{Path: path, Size: size})
				}

				// Aggregate to parent dir
				dir := filepath.Dir(path)
				dirSizes[dir] += size
			}
			return nil
		})

		if err != nil && err != context.Canceled {
			// Log error if needed, but continue
		}
	}

	report := &DiskReport{
		TopFiles: extractSorted(topFiles),
	}

	// Process Top Dirs
	topDirs := &FileHeap{}
	heap.Init(topDirs)
	for path, size := range dirSizes {
		if topDirs.Len() < opts.TopK {
			heap.Push(topDirs, FileEntry{Path: path, Size: size})
		} else if size > (*topDirs)[0].Size {
			heap.Pop(topDirs)
			heap.Push(topDirs, FileEntry{Path: path, Size: size})
		}
	}
	report.TopDirs = extractSorted(topDirs)

	return report, nil
}

func extractSorted(h *FileHeap) []FileEntry {
	res := make([]FileEntry, 0, h.Len())
	for h.Len() > 0 {
		res = append(res, heap.Pop(h).(FileEntry))
	}
	// Reverse to get descending
	for i, j := 0, len(res)-1; i < j; i, j = i+1, j-1 {
		res[i], res[j] = res[j], res[i]
	}
	return res
}
