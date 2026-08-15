# syntax=docker/dockerfile:1
# Test image for the dsh web GUI in a containerized (remote-style) deployment.
# Build from the repository root:  docker build -t dsh-web .
#
# What this image proves at runtime:
#   - directory-picker-auto resolves `browse` (bind 0.0.0.0 != 127.0.0.1), so the
#     in-web Miller directory browser lists the CONTAINER filesystem — no OS dialog.
#   - Pasted-image intake is browser-side (clipboardData -> base64 upload), so it
#     works with zero clipboard on the server.

FROM node:24-bookworm-slim

# python3/make/g++: node-gyp fallback for native deps (koffi, landlock addon).
# git: runtime repo-context reads. ca-certificates: registry + provider TLS.
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3 make g++ git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /repo

# Sources only; .dockerignore keeps node_modules, build outputs, and .env out.
COPY . .

# corepack resolves pnpm@11.7.0 from the root packageManager field.
RUN corepack enable && pnpm install --frozen-lockfile

# Full build: host/client lib (tsc + tsdown) and the web frontend dist (vite).
# The web-app row refuses to boot without @deepseek-ai/dsh-web-frontend/dist.
RUN pnpm run build

# Bind all interfaces. The CLI deliberately refuses `--host 0.0.0.0` (it would
# expose RCE to the network), so the webserver row is patched instead: a config
# patch REPLACES the row's complete config, and both fields are required —
# the original !!js webStartup reads are gone, so port is pinned here too.
COPY <<'EOF' /dsh-docker.yml
- id: webserver
  config:
    host: '0.0.0.0'
    port: 3080
EOF

# Sessions, settings, and credentials survive container replacement.
ENV DSH_HOME=/data
RUN mkdir -p /data
VOLUME /data

EXPOSE 3080

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:3080/').then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"

# DEEPSEEK_API_KEY is optional at boot (UI and directory browsing work without
# it); pass -e DEEPSEEK_API_KEY=... for real model calls.
CMD ["pnpm", "dsh", "web", "--patch", "/dsh-docker.yml"]
