package monitor

import (
	"fmt"
)

// MonitoringReport summarizes the current state of TCP connections
type MonitoringReport struct {
	TotalConnections int
	ByState         map[SocketState]int
	HighBacklogPorts []int // Ports with non-zero Rx/Tx queues
}

// AnalyzeConnections performs a high-level audit of the connection pool
func AnalyzeConnections(sockets []SocketInfo) MonitoringReport {
	report := MonitoringReport{
		TotalConnections: len(sockets),
		ByState:         make(map[SocketState]int),
	}

	backlogPorts := make(map[int]bool)

	for _, s := range sockets {
		report.ByState[s.State]++
		if s.RxQueue > 0 || s.TxQueue > 0 {
			backlogPorts[s.LocalPort] = true
		}
	}

	for p := range backlogPorts {
		report.HighBacklogPorts = append(report.HighBacklogPorts, p)
	}

	return report
}

// DetectThunderingHerd checks for signs of a thundering herd (many SYN_RECV)
func DetectThunderingHerd(sockets []SocketInfo, threshold int) (bool, string) {
	synRecvCount := 0
	for _, s := range sockets {
		if s.State == StateSynRecv {
			synRecvCount++
		}
	}

	if synRecvCount > threshold {
		return true, fmt.Sprintf("Thundering Herd Detected: %d connections in SYN_RECV state (threshold: %d)", synRecvCount, threshold)
	}

	return false, ""
}
