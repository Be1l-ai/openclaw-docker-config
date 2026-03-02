#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# HF Spaces Entrypoint
# =============================================================================
# 1. Copies baked-in config to OPENCLAW_HOME (first-run, no-clobber)
# 2. Seeds workspace templates
# 3. Installs ClawHub skills from the manifest
# 4. Hands off to the CMD (openclaw gateway)
# =============================================================================

CONFIG_SRC="/app/config"
CONFIG_DST="${OPENCLAW_HOME:-/app/data}"
WORKDIR="$CONFIG_DST/workspace"
MANIFEST="$CONFIG_SRC/skills-manifest.txt"
TEMPLATES="/app/workspace-templates"

###############################################################################
# 1. Seed config files into OPENCLAW_HOME (no-clobber)
###############################################################################
echo "[hf-entrypoint] Setting up config in $CONFIG_DST ..."
for f in openclaw.json security-rules.md SOUL.md HEARTBEAT.md; do
  if [[ -f "$CONFIG_SRC/$f" ]]; then
    cp -n "$CONFIG_SRC/$f" "$CONFIG_DST/$f" 2>/dev/null || true
  fi
done

###############################################################################
# 2. Seed workspace templates (no-clobber — won't overwrite existing files)
###############################################################################
if [[ -d "$TEMPLATES" ]]; then
  echo "[hf-entrypoint] Seeding workspace templates ..."
  mkdir -p "$WORKDIR"
  cp -rn "$TEMPLATES"/. "$WORKDIR"/
fi

# Create well-known directories used by HEARTBEAT and everyday tasks
mkdir -p "$WORKDIR/Assignments"     \
         "$WORKDIR/Assignments/summaries" \
         "$WORKDIR/Documents"       \
         "$WORKDIR/Presentations"   \
         "$WORKDIR/daily-briefs"

###############################################################################
# 3. Install ClawHub skills from manifest
###############################################################################
if [[ -f "$MANIFEST" ]]; then
  echo "[hf-entrypoint] Installing ClawHub skills from manifest ..."
  while IFS= read -r line; do
    line="${line%%#*}"                     # strip comments
    line="$(echo "$line" | xargs)"        # trim whitespace
    [[ -z "$line" ]] && continue

    if [[ -d "$WORKDIR/skills/$line" ]]; then
      echo "[hf-entrypoint]   ✓ $line (cached)"
      continue
    fi

    echo "[hf-entrypoint]   → installing $line"
    clawhub install "$line" --workdir "$WORKDIR" || {
      echo "[hf-entrypoint] WARNING: Failed to install $line — continuing"
    }
  done < "$MANIFEST"
  echo "[hf-entrypoint] Skill installation complete."
else
  echo "[hf-entrypoint] No skills manifest found — skipping."
fi

###############################################################################
# 4. Hand off to CMD
###############################################################################
echo "[hf-entrypoint] Starting OpenClaw gateway on port ${OPENCLAW_GATEWAY_PORT:-7860} ..."
exec "$@"
