package api

import (
	"context"

	"github.com/dillybert/core-api/generated/ogen"
	"go.uber.org/zap"
)

type HealthChecker interface {
	Ping(context.Context) error
}

type Handler struct {
	logger *zap.Logger
	health HealthChecker
}

func NewHandler(logger *zap.Logger, health HealthChecker) (*Handler, error) {
	return &Handler{
		logger: logger,
		health: health,
	}, nil
}

func (h *Handler) Health(ctx context.Context) (ogen.HealthRes, error) {
	if err := h.health.Ping(ctx); err != nil {
		h.logger.Error("health check failed", zap.Error(err))
		return &ogen.ErrorResponse{
			Code:    "dependency_unavailable",
			Message: "Service temporarely unavailable",
		}, nil
	}

	return &ogen.HealthResponse{
		Status: ogen.HealthResponseStatusOk,
	}, nil
}
