package incident

import (
	"context"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"
)

// LoadCheck implements system load checking
type LoadCheck struct {
	MaxLoad float64
}

func (c *LoadCheck) Name() string {
	return "System Load"
}

func (c *LoadCheck) Run(ctx context.Context) ([]Incident, error) {
	data, err := os.ReadFile("/proc/loadavg")
	if err != nil {
		return nil, fmt.Errorf("failed to read loadavg: %w", err)
	}

	fields := strings.Fields(string(data))
	if len(fields) < 1 {
		return nil, fmt.Errorf("invalid loadavg format")
	}

	load1, err := strconv.ParseFloat(fields[0], 64)
	if err != nil {
		return nil, fmt.Errorf("failed to parse load: %w", err)
	}

	if load1 > c.MaxLoad {
		return []Incident{{
			CheckName:   c.Name(),
			Description: fmt.Sprintf("load average 1m (%.2f) exceeds threshold (%.2f)", load1, c.MaxLoad),
		}}, nil
	}
	return nil, nil
}

// ServiceCheck implements critical port checking
type ServiceCheck struct {
	ServiceName string
	Port        int
}

func (c *ServiceCheck) Name() string {
	return fmt.Sprintf("Service: %s", c.ServiceName)
}

func (c *ServiceCheck) Run(ctx context.Context) ([]Incident, error) {
	addr := fmt.Sprintf("localhost:%d", c.Port)
	dialer := net.Dialer{Timeout: 2 * time.Second}

	conn, err := dialer.DialContext(ctx, "tcp", addr)
	if err != nil {
		return []Incident{{
			CheckName:   c.Name(),
			Description: fmt.Sprintf("service %s (port %d) unreachable: %v", c.ServiceName, c.Port, err),
			Remediation: &ServiceRestart{ServiceName: c.ServiceName},
		}}, nil
	}
	defer conn.Close()
	return nil, nil
}
