# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.27.2
ARG GOLANGCI_LINT_VERSION=v2.15.0

# ---------- dependencies ----------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS deps

WORKDIR /src

# Нужен для CGO и race detector.
RUN apk add --no-cache build-base

COPY go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download && go mod verify

COPY . .

# ---------- quality ----------
FROM deps AS quality

ARG GOLANGCI_LINT_VERSION

# Устанавливаем зафиксированную версию линтера.
RUN --mount=type=cache,target=/go/pkg/mod \
    go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}

# Проверка форматирования.
RUN test -z "$(gofmt -l .)"

# Статический анализ.
RUN --mount=type=cache,target=/go/pkg/mod \
    go vet ./...

# Обычные тесты.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go test ./...

# Race detector.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go test -race ./...

# Линтер.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    golangci-lint run ./...

# ---------- builder ----------
# Builder не запустится, пока quality не завершится успешно.
FROM quality AS builder

ARG APP_VERSION=dev
ARG APP_COMMIT=unknown
ARG TARGETARCH

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -tags timetzdata \
      -ldflags="-s -w -X main.version=${APP_VERSION} -X main.commit=${APP_COMMIT}" \
      -o /out/core-api \
      ./cmd/core-api

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -tags timetzdata \
      -ldflags="-s -w" \
      -o /out/core-cli \
      ./cmd/core-cli

RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=${TARGETARCH} \
    go build \
      -trimpath \
      -tags timetzdata \
      -ldflags="-s -w" \
      -o /out/healthcheck \
      ./cmd/healthcheck

# ---------- runtime ----------
FROM scratch

COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /out/core-api /core-api
COPY --from=builder /out/core-cli /core-cli
COPY --from=builder /out/healthcheck /healthcheck

COPY <<EOF /etc/passwd
nonroot:x:65532:65532:nonroot:/tmp:/sbin/nologin
EOF

COPY <<EOF /etc/group
nonroot:x:65532:
EOF

ENV HOME=/tmp

WORKDIR /tmp

USER 65532:65532

EXPOSE 8080

ENTRYPOINT ["/core-api"]
