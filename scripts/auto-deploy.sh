#!/bin/bash
# Auto-deploy script: checks for upstream git changes and rebuilds if needed.
# Set up as a cron job: */5 * * * * /path/to/scripts/auto-deploy.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${REPO_DIR}/scripts/deploy.log"
BRANCH="main"
MAX_LOG_LINES=500
# Records the remote commit whose deploy failed, so the same failure isn't retried (and logged) every run
FAILED_MARK="${REPO_DIR}/.git/auto-deploy-failed"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Keep log file from growing unbounded
if [ -f "$LOG_FILE" ] && [ "$(wc -l < "$LOG_FILE")" -gt "$MAX_LOG_LINES" ]; then
  tail -n $((MAX_LOG_LINES / 2)) "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
fi

cd "$REPO_DIR"

git fetch origin "$BRANCH" --quiet

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/$BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
  rm -f "$FAILED_MARK"
  exit 0
fi

# Already failed on this exact remote commit: wait for a manual fix or a new commit
if [ -f "$FAILED_MARK" ] && [ "$(cat "$FAILED_MARK")" = "$REMOTE" ]; then
  exit 0
fi

log "New commits detected: $LOCAL → $REMOTE"
CHANGED=$(git diff --name-only "$LOCAL" "$REMOTE")

log "Pulling latest changes..."
if ! git pull --ff-only origin "$BRANCH"; then
  echo "$REMOTE" > "$FAILED_MARK"
  log "ERROR: git pull failed (local changes or non-fast-forward); deploy stuck at $LOCAL."
  log "ERROR: fix manually in $REPO_DIR (see 'git status'). Will retry automatically on the next new commit."
  exit 1
fi

log "Rebuilding site..."
docker compose --profile build run --rm hugo-build

log "Build complete."

# Caddyfile is a single-file bind mount: git replaces the file (new inode), so the running
# container keeps the old content until it is recreated. Validate first so a broken
# Caddyfile never takes down the running Caddy.
if echo "$CHANGED" | grep -qxE 'Caddyfile|docker-compose\.ya?ml'; then
  log "Caddy config changed, validating..."
  if ! docker run --rm \
      -v "${REPO_DIR}/Caddyfile:/etc/caddy/Caddyfile:ro" \
      -v "${REPO_DIR}/caddy_config:/config:ro" \
      caddy:alpine caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>&1; then
    log "ERROR: new Caddyfile failed validation; Caddy NOT recreated (still serving the previous config)."
    log "ERROR: fix the Caddyfile and push again; the next commit that touches it will be re-validated."
    exit 1
  fi
  log "Recreating Caddy container..."
  docker compose --profile prod up -d --force-recreate web
  log "Caddy recreated."
fi
