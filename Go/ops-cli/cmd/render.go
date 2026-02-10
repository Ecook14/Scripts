package cmd

import (
	"encoding/json"
	"fmt"
)

// infoMessage is used for JSON output consistency
type infoMessage struct {
	Level   string      `json:"level"`
	Message string      `json:"message"`
	Data    interface{} `json:"data,omitempty"`
}

// render handles printing results in either plain text or JSON
func render(v interface{}, plainMsg string) {
	if jsonOutput {
		data, _ := json.MarshalIndent(v, "", "  ")
		fmt.Println(string(data))
	} else {
		if plainMsg != "" {
			fmt.Println(plainMsg)
		}
		// If v is complex, we might want a stringer, but for now we expect plainMsg to cover it
	}
}

// renderStatus is for single status messages
func renderStatus(level, msg string, data interface{}) {
	if jsonOutput {
		m := infoMessage{Level: level, Message: msg, Data: data}
		out, _ := json.Marshal(m)
		fmt.Println(string(out))
	} else {
		fmt.Printf("[%s] %s\n", level, msg)
	}
}
