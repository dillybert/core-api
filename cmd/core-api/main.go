package main

import (
	"context"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/dillybert/core-api/generated/ogen"
	"github.com/dillybert/core-api/internal/api"
	"github.com/jackc/pgx/v5/pgxpool"
	"go.uber.org/zap"
)

var (
	version = "unknown"
	commit  = "0"
)

func main() {
	logger, err := zap.NewProduction()
	if err != nil {
		fmt.Errorf("logger initializing error: %s\n", err)
	}
	defer logger.Sync()

	if err := run(logger); err != nil {
		logger.Error("failed to start api server",
			zap.Error(err),
		)
		os.Exit(1)
	}
}

func run(logger *zap.Logger) error {
	logger.Info("info",
		zap.String("version", version),
		zap.String("commit", commit),
	)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := pgxpool.New(ctx, os.Getenv("DATABASE_URL"))
	if err != nil {
		return fmt.Errorf("failed to open database %s: %w", os.Getenv("DATABASE_URL"), err)
	}
	defer pool.Close()

	handler, err := api.NewHandler(logger, pool)
	if err != nil {
		return fmt.Errorf("failed to create api handler", zap.Error(err))
	}

	api, err := ogen.NewServer(handler)
	if err != nil {
		return fmt.Errorf("failed to create api", zap.Error(err))
	}

	server := &http.Server{
		Addr:              os.Getenv("HTTP_ADDR"),
		Handler:           api,
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       10 * time.Second,
		WriteTimeout:      15 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	serverErr := make(chan error, 1)
	go func() {
		logger.Info("core-api server started", zap.String("addr", os.Getenv("HTTP_ADDR")))
		serverErr <- server.ListenAndServe()
	}()

	select {
	case <-ctx.Done():
		shutDownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()

		if err := server.Shutdown(shutDownCtx); err != nil {
			return fmt.Errorf("failed to shutdown http server", zap.Error(err))
		}

		return nil
	case err := <-serverErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}

		return fmt.Errorf("serve error: %w", err)
	}
}
