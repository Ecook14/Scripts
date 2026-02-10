package forensics

import (
	"bufio"
	"context"
	"fmt"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Result represents a file matching a malicious signature
type Result struct {
	Path      string
	Signature string
}

// Signature defines a malicious pattern
type Signature struct {
	Name    string
	Pattern string
}

// DefaultSignatures returns common PHP malware patterns
func DefaultSignatures() []Signature {
	return []Signature{
		{Name: "Obfuscated PHP", Pattern: "eval(base64_decode"},
		{Name: "FilesMan Shell", Pattern: "FilesMan"},
		{Name: "WSO Web Shell", Pattern: "wso_version"},
		{Name: "Suspicious Exec", Pattern: "exec($_POST"},
		{Name: "Suspicious System", Pattern: "system($_GET"},
		{Name: "R57 Shell", Pattern: "r57shell"},
		{Name: "C99 Shell", Pattern: "c99shell"},
		// Miner Signatures
		{Name: "XMRig Miner", Pattern: "xmrig"},
		{Name: "Stratum Protocol", Pattern: "stratum+tcp"},
		{Name: "Cryptonight Algo", Pattern: "cryptonight"},
		{Name: "Miner Config (json)", Pattern: "\"donate-level\":"},
		{Name: "Miner Pool", Pattern: "pool.supportxmr.com"},
	}
}

// Scanner performs parallel scanning for malware
type Scanner struct {
	Root       string
	Signatures []Signature
	Workers    int
}

// Scan walks the directory and scans files in parallel
func (s *Scanner) Scan(ctx context.Context) ([]Result, error) {
	if s.Workers == 0 {
		s.Workers = 4 // Default concurrency
	}

	results := make(chan Result)
	files := make(chan string)
	var wg sync.WaitGroup

	// Start worker pool
	for i := 0; i < s.Workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for path := range files {
				if sig := s.scanFile(path); sig != "" {
					results <- Result{Path: path, Signature: sig}
				}
			}
		}()
	}

	// Collected results
	var detected []Result
	done := make(chan struct{})
	go func() {
		for r := range results {
			detected = append(detected, r)
		}
		close(done)
	}()

	// Walk the directory
	err := filepath.WalkDir(s.Root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			slog.Warn("Failed to access path", "path", path, "error", err)
			return nil
		}
		if !d.IsDir() {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case files <- path:
			}
		}
		return nil
	})

	close(files)
	wg.Wait()
	close(results)
	<-done

	return detected, err
}

// scanFile checks a single file for signatures
// Returns the name of the first matching signature, or empty string
func (s *Scanner) scanFile(path string) string {
	f, err := os.Open(path)
	if err != nil {
		return ""
	}
	defer f.Close()

	// Only scan the first 50KB to be fast (heuristic)
	// or scan line by line if needed.
	// For malware, usually it's in the header or footer, but let's scan line by line.
	scanner := bufio.NewScanner(f)
	
	// Create a buffer for scanning large lines
	buf := make([]byte, 64*1024)
	scanner.Buffer(buf, 1024*1024)

	for scanner.Scan() {
		line := scanner.Text()
		
		// 1. Signature Check
		for _, sig := range s.Signatures {
			if strings.Contains(line, sig.Pattern) {
				return sig.Name
			}
		}
	}
	
	// 2. Entropy Check (Advanced)
	// If no signature found, check if full file entropy is abnormally high (obfuscation)
	// We scan the first 4KB as a heuristic for headers/payloads
	if _, err := f.Seek(0, 0); err == nil {
		head := make([]byte, 4096)
		n, _ := f.Read(head)
		if n > 0 {
			entropy := CalculateEntropy(head[:n])
			if entropy > 5.5 { // Threshold for suspicious randomness (e.g. Rondo encrypted payload)
				return fmt.Sprintf("High Entropy (%.2f)", entropy)
			}
		}
	}

	return ""
}
