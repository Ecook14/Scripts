//go:build !linux && !darwin

package forensics

import (
	"context"
	"fmt"
)

// IsImmutable checks if a file has the immutable attribute set (+i)
// On Windows, this translates to Read-Only (+R), System (+S) or Hidden (+H)
func IsImmutable(path string) (bool, error) {
	// Simple stub for now, or check for +R
	return false, nil
}

// MakeMutable attempts to remove the immutable attribute (-i)
// On Windows, equivalent to removing Read-Only attribute
func MakeMutable(ctx context.Context, path string) error {
	// Stub implementation
	// To perform similarly: exec.Command("attrib", "-r", "-s", "-h", path)
	return fmt.Errorf("immutable attribute handling not implemented for this OS")
}
