###############################################################################
# OpenClaw Gateway — Hugging Face Spaces (Docker SDK)
#
# Platform : HF Spaces CPU Basic (2 vCPU, 16 GB RAM, Free Tier)
# Port     : 7860 (HF requirement)
# Model    : google/gemini-2.5-flash via Google AI Studio
#
# All secrets (API keys, tokens) are injected at runtime via HF Space
# repository secrets — nothing is hardcoded here.
###############################################################################

FROM node:22-bookworm

# ── DNS: ensure reliable resolution (HF internal DNS can be flaky) ───────────
RUN echo 'nameserver 8.8.8.8' > /etc/resolv.conf.fallback \
  && echo 'nameserver 8.8.4.4' >> /etc/resolv.conf.fallback

# ── System dependencies ─────────────────────────────────────────────────────
# Chromium headless + fonts for web scraping / PDF rendering / screenshots.
# tini ensures proper PID-1 signal handling inside the container.
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    tini \
    ca-certificates \
    gnupg \
    # ── Chromium & headless rendering ──
    chromium \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    libnss3 \
    libatk-bridge2.0-0 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libasound2 \
    libpangocairo-1.0-0 \
    libgtk-3-0 \
  && rm -rf /var/lib/apt/lists/*

# ── GitHub CLI (required by the `github` ClawHub skill) ─────────────────────
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update && apt-get install -y --no-install-recommends gh \
  && rm -rf /var/lib/apt/lists/*

# ── Environment ─────────────────────────────────────────────────────────────
ENV OPENCLAW_GATEWAY_PORT=7860 \
    OPENCLAW_HOME=/app/data \
    CHROMIUM_PATH=/usr/bin/chromium \
    PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium \
    PUPPETEER_SKIP_DOWNLOAD=true \
    BROWSER_FLAGS="--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage --disable-gpu" \
    NODE_ENV=production \
    TERM=xterm-256color

# ── OpenClaw + ClawHub CLI ────────────────────────────────────────────────────
# Use npm (not pnpm) so OpenClaw's bundled plugins resolve to a trusted path
# under /usr/local/lib/node_modules/ instead of pnpm's content-addressable store.
ARG OPENCLAW_VERSION=2026.3.1

RUN npm install -g openclaw@${OPENCLAW_VERSION} clawhub

# ── App directory structure ─────────────────────────────────────────────────────
# /app/data    → OPENCLAW_HOME  (config, workspace, runtime state)
# /app/config  → baked-in config files (copied to data dir at first boot)
# ~/.openclaw  → where OpenClaw CLI looks for config at runtime
RUN mkdir -p /app/data/.openclaw /app/data/workspace/skills /app/config /.clawhub \
  && chown -R node:node /app /.clawhub

COPY --chown=node:node config/                /app/config/
COPY --chown=node:node workspace-templates/   /app/workspace-templates/
COPY --chown=node:node entrypoint.sh          /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ── Run as non-root (node = UID 1000) ───────────────────────────────────────
USER node
WORKDIR /app

EXPOSE 7860

ENTRYPOINT ["tini", "--", "entrypoint.sh"]
CMD ["openclaw", "gateway", "--bind", "lan", "--port", "7860"]
