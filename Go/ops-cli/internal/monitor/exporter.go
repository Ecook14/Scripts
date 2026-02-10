package monitor

import (
	"fmt"
	"net/http"
	"sync"
)

// Exporter serves metrics in Prometheus format
type Exporter struct {
	mu      sync.Mutex
	metrics map[string]float64
}

// NewExporter initializes the exporter
func NewExporter() *Exporter {
	return &Exporter{
		metrics: make(map[string]float64),
	}
}

// UpdateMetric sets a value for a metric
func (e *Exporter) UpdateMetric(name string, value float64) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.metrics[name] = value
}

// ServeHTTP implements the http.Handler interface
func (e *Exporter) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	e.mu.Lock()
	defer e.mu.Unlock()

	for name, val := range e.metrics {
		fmt.Fprintf(w, "ops_cli_%s %f\n", name, val)
	}
}

// StartExporter begins listening on the specified addr
func (e *Exporter) StartExporter(addr string) error {
	http.Handle("/metrics", e)
	return http.ListenAndServe(addr, nil)
}
