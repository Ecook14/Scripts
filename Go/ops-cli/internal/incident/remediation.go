package incident

import (
	"context"
	"fmt"
	"os/exec"
	"strconv"
)

// ServiceRestart attempts to revitalize a service
type ServiceRestart struct {
	ServiceName string
}

func (r *ServiceRestart) Name() string {
	return fmt.Sprintf("Restart Service: %s", r.ServiceName)
}

func (r *ServiceRestart) Execute(ctx context.Context) error {
	cmd := exec.CommandContext(ctx, "systemctl", "restart", r.ServiceName)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to restart service %s: %s (%w)", r.ServiceName, out, err)
	}
	return nil
}

// ProcessKill attempts to terminate a specific process
type ProcessKill struct {
	PID int
}

func (r *ProcessKill) Name() string {
	return fmt.Sprintf("Kill Process: PID %d", r.PID)
}

func (r *ProcessKill) Execute(ctx context.Context) error {
	// Use syscall to send SIGKILL to the process
	cmd := exec.CommandContext(ctx, "kill", "-9", strconv.Itoa(r.PID))
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to kill process %d: %s (%w)", r.PID, out, err)
	}
	return nil
}
