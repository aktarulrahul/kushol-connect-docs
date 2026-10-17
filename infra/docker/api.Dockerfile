# syntax=docker/dockerfile:1
#
# Kushol Connect api image (module 15, OPS-BE-001): one static Go binary on distroless, non-root.
# Lives in the docs repo (all deploy files are under docs/infra); the build context is the api repo:
#   docker buildx build --platform linux/amd64 -f docs/infra/docker/api.Dockerfile … applications/api
# BuildKit applies api.Dockerfile.dockerignore (next to this file). Never built on the VPS
# (OPS-BR-001) — see deploy/docs/images.md. The same image runs every role, chosen by the command:
#   serve · worker · migrate-status (read-only) · migrate … --confirm (owner-run, Gate 2) · healthcheck
# Migrations, i18n catalogs and the docs page are embedded, so the image needs no other files.

# Build on the runner's native platform and cross-compile (fast on arm64 Macs too).
FROM --platform=$BUILDPLATFORM golang:1.26.8-alpine3.24@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS build
ARG TARGETOS=linux
ARG TARGETARCH=amd64
WORKDIR /src
ENV CGO_ENABLED=0
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY . .
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath -ldflags="-s -w" -o /out/api ./cmd/api

# distroless/static: CA certificates (Neon TLS) + tzdata, no shell, no package manager.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --from=build /out/api /usr/local/bin/api
USER 65532:65532
# Containers listen on 8080; the host publishes it on 127.0.0.1 only (deploy/compose.yaml).
ENV HTTP_PORT=8080
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/api"]
CMD ["serve"]
