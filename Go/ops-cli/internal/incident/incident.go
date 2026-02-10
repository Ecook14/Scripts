package incident

import (
	"context"
	"log/slog"
)

// Check defines a health check that can flag an incident
type Check interface {
	Name() string
	Run(ctx context.Context) ([]Incident, error)
}

// Remediation defines an action to fix an incident
type Remediation interface {
	Name() string
	Execute(ctx context.Context) error
}

// Incident represents a detected anomaly
type Incident struct {
	CheckName   string
	Description string
	Remediation Remediation
}

// Policy defines automated response rules
type Policy struct {
	CheckName   string `json:"check_name" yaml:"check_name"`
	AutoRemedy  bool   `json:"auto_remedy" yaml:"auto_remedy"`
	MaxRetries  int    `json:"max_retries" yaml:"max_retries"`
}

// Engine manages checks and remediations
type Engine struct {
	Checks   []Check
	DryRun   bool
	Policies []Policy
}

func (e *Engine) Run(ctx context.Context) ([]Incident, error) {
	var allIncidents []Incident

	for _, check := range e.Checks {
		incidents, err := check.Run(ctx)
		if err != nil {
			slog.Warn("Check failed to execute", "check", check.Name(), "error", err)
			continue
		}
		allIncidents = append(allIncidents, incidents...)
	}
	return allIncidents, nil
}
