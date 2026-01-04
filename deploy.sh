#!/bin/bash
# Local Maven deploy script - uses system SSH config
set -euo pipefail

usage() {
    echo "Usage: $0 user@host[:port] [path]"
    echo "  Deploys Maven artifacts via SSH/rsync using system SSH config"
    exit 1
}

[ $# -lt 1 ] && usage

REMOTE="$1"
REPO_PATH="${2:-.}"

# Parse user@host:port into REMOTE (user@host) and SSH_PORT
# Regex breakdown:
#   ^([^@]+@)?    -> Group 1: Optional 'user@'
#   ([^:]+)       -> Group 2: Hostname (stops at first colon)
#   (:([0-9]+))?$ -> Group 3: Optional ':port' (Group 4 captures digits)
if [[ "$REMOTE" =~ ^([^@]+@)?([^:]+)(:([0-9]+))?$ ]]; then
    REMOTE="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"  # Reconstruct user@host
    SSH_PORT="${BASH_REMATCH[4]:-22}"              # Use captured port or default to 22
else
    echo "Error: Invalid format '$REMOTE'. Expected: [user@]host[:port]"
    exit 1
fi

[ ! -f "./mvnw" ] && { echo "Error: ./mvnw not found"; exit 1; }

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

STAGING="${TMPDIR_WORK}/repo"
mkdir -p "${STAGING}"

SSH_CMD="ssh -p ${SSH_PORT}"

echo "Fetching metadata from ${REMOTE}:${REPO_PATH}..."
rsync -am --no-links --no-devices --no-specials -e "${SSH_CMD}" \
    --include='*/' \
    --include='maven-metadata.xml*' \
    --exclude='*' \
    "${REMOTE}:${REPO_PATH}/" "${STAGING}/" 2>/dev/null || true

echo "Building..."
./mvnw -B deploy -DaltDeploymentRepository=local::default::file://"${STAGING}"

echo "Uploading to ${REMOTE}:${REPO_PATH}..."
rsync -rptv --no-links --no-devices --no-specials -e "${SSH_CMD}" "${STAGING}/" "${REMOTE}:${REPO_PATH}/"

echo "Done."
