#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# OpenClaw HF Spaces — Entrypoint
# =============================================================================
# 1. Seeds baked-in config into OPENCLAW_HOME (first-run, no-clobber)
# 2. Seeds workspace templates
# 3. Installs ClawHub skills from the manifest
# 4. Hands off to CMD (openclaw gateway)
# =============================================================================

CONFIG_SRC="/app/config"
OCLAW_HOME="${OPENCLAW_HOME:-/app/data}"
STATE_DIR="$OCLAW_HOME/.openclaw"      # where OpenClaw actually reads config/state
WORKDIR="$OCLAW_HOME/workspace"
MANIFEST="$CONFIG_SRC/skills-manifest.txt"
TEMPLATES="/app/workspace-templates"

###############################################################################
# 1. Seed config files into $OPENCLAW_HOME/.openclaw/  (the ONLY state dir)
###############################################################################
# OpenClaw reads config from $OPENCLAW_HOME/.openclaw/openclaw.json.
# Force-copy every boot so config stays in sync with the image.
echo "[entrypoint] Setting up config in $STATE_DIR ..."
mkdir -p "$STATE_DIR/agents/main/sessions" \
         "$STATE_DIR/credentials" \
         "$STATE_DIR/logs"
for f in openclaw.json security-rules.md SOUL.md HEARTBEAT.md; do
  if [[ -f "$CONFIG_SRC/$f" ]]; then
    cp -f "$CONFIG_SRC/$f" "$STATE_DIR/$f"
  fi
done

# Lock down permissions (doctor expects 700 / 600)
chmod 700 "$STATE_DIR"
chmod 600 "$STATE_DIR/openclaw.json" 2>/dev/null || true

# Symlink workspace into the state dir so the CLI resolves it
if [[ ! -e "$STATE_DIR/workspace" ]]; then
  ln -s "$WORKDIR" "$STATE_DIR/workspace"
fi

# Ensure a single state directory — remove any real ~/.openclaw dir/symlink
# that doesn't already point to STATE_DIR, then symlink it.
if [[ -e "$HOME/.openclaw" || -L "$HOME/.openclaw" ]]; then
  RESOLVED="$(realpath "$HOME/.openclaw" 2>/dev/null || echo NONE)"
  if [[ "$RESOLVED" != "$(realpath "$STATE_DIR")" ]]; then
    rm -rf "$HOME/.openclaw"
  fi
fi
if [[ ! -e "$HOME/.openclaw" ]]; then
  ln -sf "$STATE_DIR" "$HOME/.openclaw"
fi

###############################################################################
# 2. Seed workspace templates (no-clobber)
###############################################################################
if [[ -d "$TEMPLATES" ]]; then
  echo "[entrypoint] Seeding workspace templates ..."
  mkdir -p "$WORKDIR"
  cp -rn "$TEMPLATES"/. "$WORKDIR"/
fi

# Create well-known directories used by HEARTBEAT and everyday tasks
mkdir -p "$WORKDIR/Assignments"             \
         "$WORKDIR/Assignments/summaries"   \
         "$WORKDIR/Documents"               \
         "$WORKDIR/Presentations"           \
         "$WORKDIR/daily-briefs"

###############################################################################
# 3. Install ClawHub skills from manifest
###############################################################################
if [[ -f "$MANIFEST" ]]; then
  echo "[entrypoint] Installing ClawHub skills from manifest ..."
  while IFS= read -r line; do
    line="${line%%#*}"                     # strip comments
    line="$(echo "$line" | xargs)"        # trim whitespace
    [[ -z "$line" ]] && continue

    if [[ -d "$WORKDIR/skills/$line" ]]; then
      echo "[entrypoint]   ✓ $line (cached)"
      continue
    fi

    echo "[entrypoint]   → installing $line"
    clawhub install "$line" --force --workdir "$WORKDIR" || {
      echo "[entrypoint] WARNING: Failed to install $line — continuing"
    }
  done < "$MANIFEST"
  echo "[entrypoint] Skill installation complete."
else
  echo "[entrypoint] No skills manifest found — skipping."
fi

###############################################################################
# 4. Report storage mode
###############################################################################
STORAGE_MODE="${STORAGE_MODE:-local}"
if [[ "$STORAGE_MODE" == "supabase" ]]; then
  if [[ -n "${SUPABASE_URL:-}" && -n "${SUPABASE_SERVICE_ROLE_KEY:-}" ]]; then
    echo "[entrypoint] Storage: Supabase (${SUPABASE_URL})"
    echo "[entrypoint]   Database: conversations, memory, agent state"
    echo "[entrypoint]   File storage bucket: ${SUPABASE_STORAGE_BUCKET:-openclaw-workspace}"
  else
    echo "[entrypoint] WARNING: STORAGE_MODE=supabase but SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY is missing"
    echo "[entrypoint]   Falling back to local storage (data will not persist across restarts)"
  fi
else
  echo "[entrypoint] Storage: local (ephemeral — data lost on container restart)"
  echo "[entrypoint]   Tip: Set STORAGE_MODE=supabase for persistent storage"
fi

###############################################################################
# 5. Export GEMINI_API_KEY for semantic memory / embeddings
###############################################################################
# OpenClaw memory search needs a known embedding key.
# Re-use the same Google AI Studio key the user already provides.
if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
  export GEMINI_API_KEY="$GOOGLE_API_KEY"
  echo "[entrypoint] GEMINI_API_KEY exported from GOOGLE_API_KEY (for embeddings)"
fi

###############################################################################
# 6. Network checks (DNS & Telegram API reachability)
###############################################################################
# Append Google public DNS as fallback if resolution is unreliable
if ! getent hosts api.telegram.org >/dev/null 2>&1; then
  echo "[entrypoint] WARNING: Cannot resolve api.telegram.org with default DNS"
  if [[ -w /etc/resolv.conf ]]; then
    echo "nameserver 8.8.8.8" >> /etc/resolv.conf
    echo "nameserver 8.8.4.4" >> /etc/resolv.conf
    echo "[entrypoint] Added Google DNS fallback to /etc/resolv.conf"
  else
    echo "[entrypoint] /etc/resolv.conf not writable — setting NODE_DNS_RESULT_ORDER"
  fi
fi

# Quick connectivity test to Telegram API
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" ]]; then
  echo "[entrypoint] Testing Telegram API connectivity ..."
  HTTP_CODE=$(curl -sf -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 15 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" == "200" ]]; then
    echo "[entrypoint] Telegram API: reachable (HTTP $HTTP_CODE)"
  elif [[ "$HTTP_CODE" == "401" ]]; then
    echo "[entrypoint] ERROR: Telegram bot token is INVALID (HTTP 401). Check TELEGRAM_BOT_TOKEN in HF secrets."
  elif [[ "$HTTP_CODE" == "000" ]]; then
    echo "[entrypoint] WARNING: Cannot reach api.telegram.org — network blocked or DNS failure"
    echo "[entrypoint]   Telegram will not work until outbound HTTPS is available"
  else
    echo "[entrypoint] Telegram API: unexpected response (HTTP $HTTP_CODE)"
  fi
else
  echo "[entrypoint] TELEGRAM_BOT_TOKEN not set — Telegram channel disabled"
fi

###############################################################################
# 7. Auto-fix config migrations (telegram auto-enable, legacy keys, etc.)
###############################################################################
echo "[entrypoint] Running openclaw doctor --fix ..."
openclaw doctor --fix 2>&1 || {
  echo "[entrypoint] WARNING: openclaw doctor --fix had issues — continuing"
}

###############################################################################
# 8. Start gateway & auto-approve first pending device
###############################################################################
# Start the gateway in the background so we can run CLI commands against it.
# This is the "foreground" mode the doctor recommends for containers —
# we manage the PID ourselves instead of relying on systemd.
echo "[entrypoint] Starting OpenClaw gateway on port ${OPENCLAW_GATEWAY_PORT:-7860} ..."
"$@" &
GATEWAY_PID=$!

# Wait for gateway to be ready (up to 30 s)
echo "[entrypoint] Waiting for gateway to accept connections ..."
for i in $(seq 1 30); do
  if curl -sf http://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-7860}/health >/dev/null 2>&1; then
    echo "[entrypoint] Gateway is ready."
    break
  fi
  sleep 1
done

# Auto-approve the first pending device request (that's us via the web UI)
echo "[entrypoint] Auto-approving pending device requests ..."
sleep 3   # give the first WS connection a moment to register
REQUEST_ID=$(openclaw devices list 2>/dev/null | grep -oP '(?<=id:\s)\S+' | head -1 || true)
if [[ -z "$REQUEST_ID" ]]; then
  # Try alternative output format
  REQUEST_ID=$(openclaw devices list 2>/dev/null | awk '/pending/{print $1; exit}' || true)
fi
if [[ -n "$REQUEST_ID" ]]; then
  openclaw devices approve "$REQUEST_ID" 2>/dev/null && \
    echo "[entrypoint] Approved device: $REQUEST_ID" || \
    echo "[entrypoint] WARNING: Failed to approve device $REQUEST_ID"
else
  echo "[entrypoint] No pending device requests found (will approve on first web connection)."
fi

# Keep a background loop that checks for new pending devices every 30s
# for the first 5 minutes (covers slow first-connect scenarios)
(
  for attempt in $(seq 1 10); do
    sleep 30
    PENDING=$(openclaw devices list 2>/dev/null | grep -i pending || true)
    if [[ -n "$PENDING" ]]; then
      RID=$(echo "$PENDING" | grep -oP '(?<=id:\s)\S+' | head -1 || echo "")
      [[ -z "$RID" ]] && RID=$(echo "$PENDING" | awk '{print $1; exit}')
      if [[ -n "$RID" ]]; then
        openclaw devices approve "$RID" 2>/dev/null && \
          echo "[entrypoint] Auto-approved device: $RID"
      fi
    fi
  done
) &

# Wait on the gateway — if it exits, the container exits
wait $GATEWAY_PID
