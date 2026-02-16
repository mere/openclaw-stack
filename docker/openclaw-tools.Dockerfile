# syntax=docker/dockerfile:1.6

ARG OPENCLAW_BASE_IMAGE=ghcr.io/openclaw/openclaw:main
FROM ${OPENCLAW_BASE_IMAGE}

USER root
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG HIMALAYA_VERSION=v1.1.0

# Core CLI dependencies
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl jq git \
 && rm -rf /var/lib/apt/lists/*

# Bitwarden CLI
RUN npm i -g @bitwarden/cli

# Himalaya mail CLI (official release artifact)
RUN case "${TARGETARCH}" in \
      amd64) HIMALAYA_ARCH="x86_64" ;; \
      arm64) HIMALAYA_ARCH="aarch64" ;; \
      *) echo "Unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL -o /tmp/himalaya.tgz "https://github.com/pimalaya/himalaya/releases/download/${HIMALAYA_VERSION}/himalaya.${HIMALAYA_ARCH}-linux.tgz" \
 && tar -xzf /tmp/himalaya.tgz -C /usr/local/bin himalaya \
 && chmod +x /usr/local/bin/himalaya \
 && rm -f /tmp/himalaya.tgz

USER node
