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
CONFIG_DST="${OPENCLAW_HOME:-/app/data}"
OCLAW_DIR="$HOME/.openclaw"
WORKDIR="$CONFIG_DST/workspace"
MANIFEST="$CONFIG_SRC/skills-manifest.txt"
TEMPLATES="/app/workspace-templates"

###############################################################################
# 1. Seed config files into OPENCLAW_HOME and ~/.openclaw/
###############################################################################
# Force-copy to ~/.openclaw/ (always overwrite — ensures config is fresh).
# No-clobber copy to OPENCLAW_HOME (preserves user edits at runtime).
echo "[entrypoint] Setting up config in $CONFIG_DST ..."
mkdir -p "$OCLAW_DIR"
for f in openclaw.json security-rules.md SOUL.md HEARTBEAT.md; do
  if [[ -f "$CONFIG_SRC/$f" ]]; then
    cp -n "$CONFIG_SRC/$f" "$CONFIG_DST/$f" 2>/dev/null || true
    cp -f "$CONFIG_SRC/$f" "$OCLAW_DIR/$f"
  fi
done

# Symlink workspace into ~/.openclaw so OpenClaw CLI resolves it
if [[ ! -e "$OCLAW_DIR/workspace" ]]; then
  ln -s "$WORKDIR" "$OCLAW_DIR/workspace"
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
# 5. Auto-fix config migrations (telegram auto-enable, legacy keys, etc.)
###############################################################################
echo "[entrypoint] Running openclaw doctor --fix ..."
openclaw doctor --fix 2>&1 || {
  echo "[entrypoint] WARNING: openclaw doctor --fix had issues — continuing"
}

###############################################################################
# 6. Hand off to CMD
###############################################################################
echo "[entrypoint] Starting OpenClaw gateway on port ${OPENCLAW_GATEWAY_PORT:-7860} ..."
exec "$@"
