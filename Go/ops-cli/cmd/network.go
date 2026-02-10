package cmd

import (
	"fmt"
	"log/slog"
	"ops-cli/internal/network"

	"github.com/spf13/cobra"
)

var (
	targetIP string
)

// networkCmd represents the network command
var networkCmd = &cobra.Command{
	Use:   "network",
	Short: "Network security and firewall management",
	Long:  `Check and unblock IP addresses across common Linux firewalls.`,
}

var ipCheckCmd = &cobra.Command{
	Use:   "check",
	Short: "Check if an IP is blocked",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		if targetIP == "" {
			return fmt.Errorf("IP address required via --ip flag")
		}

		fw, err := network.CheckIP(ctx, targetIP)
		if err != nil {
			return fmt.Errorf("check failed: %w", err)
		}

		if fw != "" {
			slog.Warn("IP Block Found", "ip", targetIP, "firewall", fw)
		} else {
			slog.Info("IP is not blocked in detected firewalls", "ip", targetIP)
		}
		return nil
	},
}

var ipUnblockCmd = &cobra.Command{
	Use:   "unblock",
	Short: "Remove an IP from the firewall",
	RunE: func(cmd *cobra.Command, args []string) error {
		ctx := cmd.Context()
		if targetIP == "" {
			return fmt.Errorf("IP address required via --ip flag")
		}

		// First, find which firewall has the block
		fw, err := network.CheckIP(ctx, targetIP)
		if err != nil {
			return fmt.Errorf("failed to identify firewall: %w", err)
		}

		if fw == "" {
			slog.Info("No active block found for IP. Nothing to unblock.", "ip", targetIP)
			return nil
		}

		slog.Info("Unblocking IP", "ip", targetIP, "firewall", fw)
		if err := network.UnblockIP(ctx, targetIP, fw); err != nil {
			return fmt.Errorf("unblock failed: %w", err)
		}

		slog.Info("IP successfully unblocked", "ip", targetIP, "firewall", fw)
		return nil
	},
}

func init() {
	rootCmd.AddCommand(networkCmd)
	networkCmd.AddCommand(ipCheckCmd)
	networkCmd.AddCommand(ipUnblockCmd)

	networkCmd.PersistentFlags().StringVar(&targetIP, "ip", "", "Target IP address")
}
