#!/bin/bash
# Auto-deploy script: checks for upstream git changes and rebuilds if needed.
# Set up as a cron job: */5 * * * * /path/to/scripts/auto-deploy.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_FILE="${REPO_DIR}/scripts/deploy.log"
BRANCH="main"
MAX_LOG_LINES=500

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
  exit 0
fi

log "New commits detected: $LOCAL → $REMOTE"
log "Pulling latest changes..."
git pull origin "$BRANCH"

log "Rebuilding site..."
docker compose --profile build run --rm hugo-build

log "Build complete."
