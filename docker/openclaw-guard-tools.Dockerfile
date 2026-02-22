# syntax=docker/dockerfile:1.6

ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:main
FROM ${OPENCLAW_BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

# Core CLI dependencies (openssh-client for Admin Mode: SSH from Op to host)
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq git openssh-client \
 && rm -rf /var/lib/apt/lists/*

# Bitwarden CLI only (Himalaya and M365 run in Chloe/worker)
RUN npm i -g @bitwarden/cli

USER node
