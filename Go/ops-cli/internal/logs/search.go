package logs

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"strings"
)

// LogType defines standard log categories
type LogType string

const (
	TypeApache  LogType = "Apache"
	TypeExim    LogType = "Exim"
	TypeMySQL   LogType = "MySQL"
	TypeSystem  LogType = "System"
	TypeGeneric LogType = "Generic"
)

var LogPaths = map[LogType][]string{
	TypeApache: {"/var/log/httpd/error_log", "/var/log/apache2/error.log", "/usr/local/apache/logs/error_log"},
	TypeExim:   {"/var/log/exim_mainlog", "/var/log/exim4/mainlog"},
	TypeMySQL:  {"/var/lib/mysql/hostname.err", "/var/log/mysqld.log", "/var/log/mysql/error.log"},
	TypeSystem: {"/var/log/messages", "/var/log/syslog", "/var/log/kern.log"},
}

// SearchResult holds a matching line and its metadata
type SearchResult struct {
	Path    string `json:"path"`
	Line    int    `json:"line"`
	Content string `json:"content"`
}

// Search performs a parallelized search across log types
func Search(ctx context.Context, logType LogType, query string, limit int) ([]SearchResult, error) {
	paths := LogPaths[logType]
	if len(paths) == 0 {
		return nil, fmt.Errorf("no known paths for log type: %s", logType)
	}

	var results []SearchResult
	for _, path := range paths {
		if _, err := os.Stat(path); os.IsNotExist(err) {
			continue
		}

		f, err := os.Open(path)
		if err != nil {
			continue
		}
		defer f.Close()

		scanner := bufio.NewScanner(f)
		lineNum := 0
		for scanner.Scan() {
			lineNum++
			line := scanner.Text()
			if strings.Contains(strings.ToLower(line), strings.ToLower(query)) {
				results = append(results, SearchResult{
					Path:    path,
					Line:    lineNum,
					Content: line,
				})
			}
			if len(results) >= limit {
				break
			}
		}
	}

	return results, nil
}
