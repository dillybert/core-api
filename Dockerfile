# syntax=docker/dockerfile:1.7

ARG GO_VERSION=1.27.2

# ---------- dependencies ----------
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS deps

WORKDIR /src

COPY go.mod go.sum ./

RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download && go mod verify

COPY . .

# ---------- builder ----------
FROM deps AS builder

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
