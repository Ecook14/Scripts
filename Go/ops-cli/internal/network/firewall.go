package network

import (
	"context"
	"fmt"
	"os/exec"
	"strings"
)

// CheckIP checks if an IP is blocked in common firewalls
func CheckIP(ctx context.Context, ip string) (string, error) {
	// 1. Check CSF
	if path, err := exec.LookPath("csf"); err == nil {
		out, _ := exec.CommandContext(ctx, path, "-g", ip).CombinedOutput()
		if strings.Contains(string(out), "DENY") || strings.Contains(string(out), "TEMP") {
			return "CSF", nil
		}
	}

	// 2. Check Firewalld
	if path, err := exec.LookPath("firewall-cmd"); err == nil {
		out, _ := exec.CommandContext(ctx, path, "--list-all").CombinedOutput()
		if strings.Contains(string(out), ip) {
			return "Firewalld", nil
		}
	}

	// 3. Check Iptables
	if path, err := exec.LookPath("iptables"); err == nil {
		out, _ := exec.CommandContext(ctx, path, "-L", "-n").CombinedOutput()
		if strings.Contains(string(out), ip) {
			return "Iptables", nil
		}
	}

	return "", nil
}

// UnblockIP attempts to remove an IP from the firewall
func UnblockIP(ctx context.Context, ip string, fw string) error {
	var cmd *exec.Cmd

	switch strings.ToLower(fw) {
	case "csf":
		cmd = exec.CommandContext(ctx, "csf", "-dr", ip)
	case "firewalld":
		cmd = exec.CommandContext(ctx, "firewall-cmd", "--permanent", "--remove-rich-rule", fmt.Sprintf("rule family='ipv4' source address='%s' reject", ip))
	case "iptables":
		cmd = exec.CommandContext(ctx, "iptables", "-D", "INPUT", "-s", ip, "-j", "DROP")
	default:
		return fmt.Errorf("unsupported or unknown firewall: %s", fw)
	}

	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("failed to unblock %s via %s: %s (%w)", ip, fw, out, err)
	}

	// For Firewalld, need reload
	if fw == "firewalld" {
		_ = exec.CommandContext(ctx, "firewall-cmd", "--reload").Run()
	}

	return nil
}
