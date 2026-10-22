# syntax=docker/dockerfile:1
#
# Kushol Connect web image (module 15, OPS-BE-002): Next.js `output: "standalone"`, non-root.
# Lives in the docs repo (all deploy files are under docs/infra); the build context is the web repo:
#   docker buildx build --platform linux/amd64 -f docs/infra/docker/web.Dockerfile … applications/web
# BuildKit applies web.Dockerfile.dockerignore (next to this file). Never built on the VPS
# (OPS-BR-001) — see deploy/docs/images.md. NEXT_PUBLIC_* values are public and baked in at build
# time, so the image is built for one site origin (build args below); secrets never go in here.

FROM node:22.23.3-alpine3.24@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS base
ENV PNPM_HOME=/pnpm \
    PATH=/pnpm:$PATH \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0 \
    NEXT_TELEMETRY_DISABLED=1
# pnpm version comes from package.json "packageManager". `corepack prepare` bakes it into this
# shared (cached) base layer — without it, `corepack enable` only creates shims and the first
# `pnpm` call in later stages re-downloads pnpm from registry.npmjs.org, so a transient npmjs
# outage (HTTP 503) fails `pnpm build`.
COPY package.json ./
RUN corepack enable && corepack prepare --activate
WORKDIR /app

FROM base AS deps
COPY package.json pnpm-lock.yaml .npmrc ./
RUN --mount=type=cache,id=pnpm,target=/pnpm/store pnpm install --frozen-lockfile

FROM base AS build
ARG NEXT_PUBLIC_API_URL
ARG NEXT_PUBLIC_SITE_URL
ENV NODE_ENV=production \
    NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL \
    NEXT_PUBLIC_SITE_URL=$NEXT_PUBLIC_SITE_URL
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# src/env.ts validates both URLs here; a missing build arg fails the build (FND-BR-002).
RUN pnpm build && mkdir -p public

FROM node:22.23.3-alpine3.24@sha256:0a7108bf6c7bf5de370ffb1a3ed6be93d405b43ff159f681a8d18c0e2bc2e402 AS run
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0
COPY --from=build --chown=node:node /app/.next/standalone ./
COPY --from=build --chown=node:node /app/.next/static ./.next/static
COPY --from=build --chown=node:node /app/public ./public
USER node
EXPOSE 3000
CMD ["node", "server.js"]
