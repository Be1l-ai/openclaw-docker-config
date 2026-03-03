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
mkdir -p "$STATE_DIR"
for f in openclaw.json security-rules.md SOUL.md HEARTBEAT.md; do
  if [[ -f "$CONFIG_SRC/$f" ]]; then
    cp -f "$CONFIG_SRC/$f" "$STATE_DIR/$f"
  fi
done

# Symlink workspace into the state dir so the CLI resolves it
if [[ ! -e "$STATE_DIR/workspace" ]]; then
  ln -s "$WORKDIR" "$STATE_DIR/workspace"
fi

# Remove stale ~/.openclaw if it differs from STATE_DIR (avoids "multiple
# state directories" warning from doctor).
if [[ -d "$HOME/.openclaw" && "$(realpath "$HOME/.openclaw")" != "$(realpath "$STATE_DIR")" ]]; then
  rm -rf "$HOME/.openclaw"
fi
# Point ~/.openclaw → STATE_DIR so any CLI invocation finds the same state
if [[ ! -e "$HOME/.openclaw" ]]; then
  ln -s "$STATE_DIR" "$HOME/.openclaw"
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
# 6. Auto-fix config migrations (telegram auto-enable, legacy keys, etc.)
###############################################################################
echo "[entrypoint] Running openclaw doctor --fix ..."
openclaw doctor --fix 2>&1 || {
  echo "[entrypoint] WARNING: openclaw doctor --fix had issues — continuing"
}

###############################################################################
# 7. Hand off to CMD
###############################################################################
echo "[entrypoint] Starting OpenClaw gateway on port ${OPENCLAW_GATEWAY_PORT:-7860} ..."
exec "$@"
