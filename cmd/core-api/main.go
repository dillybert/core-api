package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dillybert/core-api/generated/ogen"
	"github.com/dillybert/core-api/internal/api"
	"github.com/dillybert/core-api/internal/env"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

var (
	version = "unknown"
	commit  = "unknown"
)

func main() {
	logger, err := zap.NewProduction()
	if err != nil {
		fmt.Fprintf(os.Stderr, "logger initialization failed: %v\n", err)
		os.Exit(1)
	}

	err = run(logger)
	if err != nil {
		logger.Error("core-api terminated with error", zap.Error(err))
	}

	if syncErr := logger.Sync(); syncErr != nil {
		fmt.Fprintf(os.Stderr, "logger sync failed: %v\n", syncErr)
	}

	if err != nil {
		os.Exit(1)
	}
}

func run(logger *zap.Logger) error {
	fmt.Printf(`
 ██████╗ █████╗ ██████╗ ██╗   ██╗███████╗ ██████╗
██╔════╝██╔══██╗██╔══██╗██║   ██║██╔════╝██╔═══██╗
██║     ███████║██████╔╝██║   ██║█████╗  ██║   ██║
██║     ██╔══██║██╔══██╗╚██╗ ██╔╝██╔══╝  ██║   ██║
╚██████╗██║  ██║██║  ██║ ╚████╔╝ ███████╗╚██████╔╝
 ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝ ╚═════╝

__________________________________________________

  CORE API  ·  TAXI DISPATCH PLATFORM
  Version: %s
  Commit:  %s
__________________________________________________

`, version, commit)

	ctx, stop := signal.NotifyContext(
		context.Background(),
		syscall.SIGINT,
		syscall.SIGTERM,
	)
	defer stop()

	dbURL := env.Get("DATABASE_URL", "")
	if dbURL == "" {
		return errors.New("DATABASE_URL is required")
	}

	pool, err := pgxpool.New(ctx, dbURL)
	if err != nil {
		return fmt.Errorf("failed to create database pool: %w", err)
	}
	defer pool.Close()

	pingCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()

	if err := pool.Ping(pingCtx); err != nil {
		return fmt.Errorf("failed to connect to database: %w", err)
	}

	handler, err := api.NewHandler(logger, pool)
	if err != nil {
		return fmt.Errorf("failed to create api handler: %w", err)
	}

	apiServer, err := ogen.NewServer(handler)
	if err != nil {
		return fmt.Errorf("failed to create ogen server: %w", err)
	}

	addr := env.Get("HTTP_ADDR", ":8080")

	server := &http.Server{
		Addr:              addr,
		Handler:           apiServer,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return fmt.Errorf("failed to listen on %s: %w", addr, err)
	}

	serverErr := make(chan error, 1)

	go func() {
		logger.Info("http server started",
			zap.String("addr", listener.Addr().String()),
		)

		serverErr <- server.Serve(listener)
	}()

	select {
	case <-ctx.Done():
		// Restore default signal handling.
		// A second SIGTERM/SIGINT can terminate the process immediately.
		stop()

		logger.Info("shutting down http server")

		shutdownCtx, cancel := context.WithTimeout(
			context.Background(),
			20*time.Second,
		)
		defer cancel()

		if err := server.Shutdown(shutdownCtx); err != nil {
			logger.Error("graceful shutdown failed",
				zap.Error(err),
			)

			// Force-close remaining connections.
			if closeErr := server.Close(); closeErr != nil {
				logger.Error("failed to force close http server",
					zap.Error(closeErr),
				)
			}

			// Wait until Serve goroutine exits.
			<-serverErr

			return fmt.Errorf("http server shutdown failed: %w", err)
		}

		// Wait until Serve goroutine exits.
		err := <-serverErr
		if err != nil && !errors.Is(err, http.ErrServerClosed) {
			return fmt.Errorf("http server stopped unexpectedly: %w", err)
		}

		logger.Info("http server stopped")
		return nil

	case err := <-serverErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}

		return fmt.Errorf("http server failed: %w", err)
	}
}
