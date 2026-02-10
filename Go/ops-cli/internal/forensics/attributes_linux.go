//go:build linux || darwin

package forensics

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// IsImmutable checks if a file has the immutable attribute set (+i)
// Note: This requires root privileges or CAP_LINUX_IMMUTABLE capability.
func IsImmutable(path string) (bool, error) {
	// Using lsattr command for simplicity and safety over raw syscalls
	cmd := exec.Command("lsattr", "-d", path)
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false, fmt.Errorf("lsattr failed: %w", err)
	}

	// Output format: ----i---------e---- /path/to/file
	attrs := strings.Fields(string(out))[0]
	return strings.Contains(attrs, "i"), nil
}

// MakeMutable attempts to remove the immutable attribute (-i)
func MakeMutable(ctx context.Context, path string) error {
	cmd := exec.CommandContext(ctx, "chattr", "-i", path)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("chattr -i failed: %s (%w)", out, err)
	}
	return nil
}
