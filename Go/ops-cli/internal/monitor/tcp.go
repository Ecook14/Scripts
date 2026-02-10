package monitor

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

// SocketState represents the state of a TCP connection
type SocketState string

const (
	StateEstablished SocketState = "ESTABLISHED"
	StateSynSent     SocketState = "SYN_SENT"
	StateSynRecv     SocketState = "SYN_RECV"
	StateFinWait1    SocketState = "FIN_WAIT1"
	StateFinWait2    SocketState = "FIN_WAIT2"
	StateTimeWait    SocketState = "TIME_WAIT"
	StateClose       SocketState = "CLOSE"
	StateCloseWait   SocketState = "CLOSE_WAIT"
	StateLastAck     SocketState = "LAST_ACK"
	StateListen      SocketState = "LISTEN"
	StateClosing     SocketState = "CLOSING"
	StateUnknown     SocketState = "UNKNOWN"
)

var stateMap = map[string]SocketState{
	"01": StateEstablished,
	"02": StateSynSent,
	"03": StateSynRecv,
	"04": StateFinWait1,
	"05": StateFinWait2,
	"06": StateTimeWait,
	"07": StateClose,
	"08": StateCloseWait,
	"09": StateLastAck,
	"0A": StateListen,
	"0B": StateClosing,
}

// SocketInfo holds details about a single TCP socket
type SocketInfo struct {
	LocalAddr  string
	LocalPort  int
	RemoteAddr string
	RemotePort int
	State      SocketState
	TxQueue    int64
	RxQueue    int64
}

// GetTCPConnections parses /proc/net/tcp and returns a list of active sockets
func GetTCPConnections() ([]SocketInfo, error) {
	return parseNetTCP("/proc/net/tcp")
}

func parseNetTCP(path string) ([]SocketInfo, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	return parseNetTCPReader(f)
}

func parseNetTCPReader(r io.Reader) ([]SocketInfo, error) {
	var sockets []SocketInfo
	scanner := bufio.NewScanner(r)

	// Skip header line
	if !scanner.Scan() {
		return nil, nil
	}

	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 4 {
			continue
		}

		localAddr, localPort := parseAddr(fields[1])
		remoteAddr, remotePort := parseAddr(fields[2])
		state := stateMap[fields[3]]
		if state == "" {
			state = StateUnknown
		}

		queues := strings.Split(fields[4], ":")
		txQ, _ := strconv.ParseInt(queues[0], 16, 64)
		rxQ, _ := strconv.ParseInt(queues[1], 16, 64)

		sockets = append(sockets, SocketInfo{
			LocalAddr:  localAddr,
			LocalPort:  localPort,
			RemoteAddr: remoteAddr,
			RemotePort: remotePort,
			State:      state,
			TxQueue:    txQ,
			RxQueue:    rxQ,
		})
	}

	return sockets, scanner.Err()
}

func parseAddr(s string) (string, int) {
	parts := strings.Split(s, ":")
	if len(parts) != 2 {
		return "", 0
	}

	ipHex, err := hex.DecodeString(parts[0])
	if err != nil {
		return "", 0
	}

	// /proc/net/tcp stores IP in little-endian hex
	var ip string
	if len(ipHex) == 4 {
		ip = fmt.Sprintf("%d.%d.%d.%d", ipHex[3], ipHex[2], ipHex[1], ipHex[0])
	} else {
		// IPv6 handling could be added here
		ip = parts[0]
	}

	port, _ := strconv.ParseInt(parts[1], 16, 32)

	return ip, int(port)
}
