package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"ops-cli/cmd"
)

func main() {
	// 5. Structured Logging vs. Standard Output
	// Use structured logging (slog) for operational info to Stderr
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	slog.SetDefault(logger)

	// 3. Graceful Signal Handling
	// Create a context that is canceled on SIGINT or SIGTERM
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()

	// Pass context to the root command (requires refactoring cmd.Execute)
	if err := cmd.Execute(ctx); err != nil {
		slog.Error("Application failed", "error", err)
		os.Exit(1)
	}
}
