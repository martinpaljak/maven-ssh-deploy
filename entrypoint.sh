#!/bin/bash
set -euo pipefail

# Validate required inputs
: "${INPUT_USER:?Error: 'user' input is required}"
: "${INPUT_KEY:?Error: 'key' input is required}"
: "${INPUT_HOST_FP:?Error: 'host_fp' input is required}"

# Validate fingerprint format (SHA256 base64, 43 chars)
if [[ ! "${INPUT_HOST_FP}" =~ ^SHA256:[A-Za-z0-9+/]{43}=?$ ]]; then
    echo "Error: Invalid fingerprint format. Expected SHA256:... (base64)"
    exit 1
fi

# Validate GitHub environment
: "${GITHUB_EVENT_NAME:?Error: not running in GitHub Actions}"
: "${GITHUB_REF_TYPE:?Error: not running in GitHub Actions}"
: "${GITHUB_REPOSITORY_OWNER:?Error: not running in GitHub Actions}"

# Inputs from composite action
SSH_USER="${INPUT_USER}"
SSH_KEY="${INPUT_KEY}"
HOST_FP="${INPUT_HOST_FP}"

# Cleanup on exit
cleanup() {
    ssh-agent -k 2>/dev/null || true
    rm -rf "${TMPDIR_WORK:-}" 2>/dev/null || true
}
trap cleanup EXIT

# --- Prerequisite Checks ---

if [ ! -f "./mvnw" ]; then
    echo "Error: Maven wrapper (./mvnw) not found. This action requires mvnw."
    exit 1
fi

if ! command -v java &> /dev/null; then
    echo "Error: Java not found. Use actions/setup-java before this action."
    exit 1
fi

echo "Using Java: $(java -version 2>&1 | head -1)"
echo "Using Maven wrapper: ./mvnw"

# --- Secure Temp Directory ---

TMPDIR_WORK=$(mktemp -d)

# --- Security Guards ---

# Skip pull requests unless explicitly allowed
if [[ "${GITHUB_EVENT_NAME}" == pull_request* ]]; then
    if [ "${INPUT_PULL:-false}" != "true" ]; then
        echo "Skipping: pull request (set 'pull: true' to deploy)"
        exit 0
    fi
    echo "Warning: Running on pull request (explicitly allowed)"
fi

# For tags, verify SSH signature by owner (unless unsigned: true)
if [ "${GITHUB_REF_TYPE}" == "tag" ] && [ "${INPUT_UNSIGNED:-false}" != "true" ]; then
    : "${GITHUB_REF_NAME:?Error: not running in GitHub Actions}"
    : "${GITHUB_TOKEN:?Error: GITHUB_TOKEN is required for tag verification}"
    TAG_NAME="${GITHUB_REF_NAME}"

    # Fetch full tag object (shallow checkout doesn't include signature)
    # + forces overwrite of existing shallow ref
    git fetch origin "+refs/tags/${TAG_NAME}:refs/tags/${TAG_NAME}"

    # Fetch owner's SSH signing keys from GitHub API
    SIGNERS_URL="https://api.github.com/users/${GITHUB_REPOSITORY_OWNER}/ssh_signing_keys"
    KEYS=$(curl -sf -H "Authorization: token ${GITHUB_TOKEN}" "$SIGNERS_URL" | jq -r '.[].key')

    if [ -z "$KEYS" ]; then
        echo "Error: No SSH signing keys found for ${GITHUB_REPOSITORY_OWNER}"
        exit 1
    fi

    # Build allowed_signers file
    SIGNERS_FILE="${TMPDIR_WORK}/allowed_signers"
    while IFS= read -r key; do
        [ -n "$key" ] && echo "${GITHUB_REPOSITORY_OWNER} ${key}" >> "$SIGNERS_FILE"
    done <<< "$KEYS"

    # Configure git (local only) and verify
    git config --local gpg.ssh.allowedSignersFile "$SIGNERS_FILE"
    if ! git tag -v "${TAG_NAME}" 2>&1; then
        echo "Error: Tag '${TAG_NAME}' signature verification failed."
        echo "Tag must be signed by ${GITHUB_REPOSITORY_OWNER}"
        exit 1
    fi
    echo "Tag '${TAG_NAME}' verified: signed by ${GITHUB_REPOSITORY_OWNER}"
fi

# --- Input Parsing ---

SSH_PORT="22"
if [ -n "${INPUT_HOST:-}" ]; then
    if [[ "${INPUT_HOST}" == *":"* ]]; then
        SSH_HOST="${INPUT_HOST%%:*}"
        SSH_PORT="${INPUT_HOST##*:}"
    else
        SSH_HOST="${INPUT_HOST}"
    fi
fi

# Parse user@host:port from INPUT_USER
if [[ "${SSH_USER}" == *"@"* ]]; then
    FULL_HOST="${SSH_USER#*@}"
    SSH_USER="${SSH_USER%%@*}"
    if [[ "${FULL_HOST}" == *":"* ]]; then
        SSH_HOST="${FULL_HOST%%:*}"
        SSH_PORT="${FULL_HOST##*:}"
    else
        SSH_HOST="${FULL_HOST}"
    fi
fi

# Validate derived values
if [ -z "${SSH_HOST:-}" ]; then
    echo "Error: SSH host is missing. Provide 'host' input or use 'user@host' format."
    exit 1
fi

if ! [[ "$SSH_PORT" =~ ^[0-9]+$ ]]; then
    echo "Error: Invalid SSH port '$SSH_PORT'. Port must be numeric."
    exit 1
fi

# Select path based on ref type
if [ "${GITHUB_REF_TYPE}" == "tag" ]; then
    REPO_PATH="${INPUT_PATH:-.}"
    echo "Release deployment to: ${REPO_PATH}"
else
    REPO_PATH="${INPUT_SNAPSHOTS:-SNAPSHOTS}"
    echo "Snapshot deployment to: ${REPO_PATH}"
fi

# --- SSH Host Fingerprint Verification ---

echo "Verifying host key for ${SSH_HOST}:${SSH_PORT}..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keyscan -p "${SSH_PORT}" "${SSH_HOST}" 2>/dev/null > "${TMPDIR_WORK}/scanned_keys" || true

if [ ! -s "${TMPDIR_WORK}/scanned_keys" ]; then
    echo "Error: Could not scan keys from ${SSH_HOST}:${SSH_PORT}"
    exit 1
fi

MATCH_FOUND=0
while IFS= read -r line; do
    echo "$line" > "${TMPDIR_WORK}/single_key"
    FP_LINE=$(ssh-keygen -lf "${TMPDIR_WORK}/single_key" 2>/dev/null) || continue
    FP_HASH=$(echo "$FP_LINE" | awk '{print $2}')
    if [ "$FP_HASH" = "${HOST_FP}" ]; then
        echo "Verified: $FP_LINE"
        cat "${TMPDIR_WORK}/single_key" >> ~/.ssh/known_hosts
        MATCH_FOUND=1
    fi
done < "${TMPDIR_WORK}/scanned_keys"

if [ "$MATCH_FOUND" -eq 0 ]; then
    echo "Error: No key matching fingerprint ${HOST_FP}"
    echo "Scanned fingerprints:"
    while IFS= read -r line; do
        echo "$line" > "${TMPDIR_WORK}/single_key"
        ssh-keygen -lf "${TMPDIR_WORK}/single_key" 2>/dev/null || true
    done < "${TMPDIR_WORK}/scanned_keys"
    exit 1
fi

chmod 600 ~/.ssh/known_hosts

# --- SSH Agent Setup ---

echo "Setting up SSH agent..."
eval "$(ssh-agent -s)" > /dev/null
ssh-add - <<< "${SSH_KEY//$'\r'/}"

SSH_CMD="ssh -p ${SSH_PORT} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=~/.ssh/known_hosts"

echo "Target: ${SSH_USER}@${SSH_HOST}:${SSH_PORT}:${REPO_PATH}"

# --- Deployment ---

STAGING="${TMPDIR_WORK}/repo"
mkdir -p "${STAGING}"

echo "Fetching remote metadata..."
rsync -rptm --no-links --no-devices --no-specials -e "${SSH_CMD}" \
    --include='*/' \
    --include='maven-metadata.xml*' \
    --exclude='*' \
    -- "${SSH_USER}@${SSH_HOST}:${REPO_PATH}/" "${STAGING}/"

echo "Deploying locally..."
./mvnw --no-transfer-progress -B -DskipTests deploy -DaltDeploymentRepository=ephemeral::file://"${STAGING}"

echo "Syncing to remote..."
rsync -rpt --no-links --no-devices --no-specials -e "${SSH_CMD}" -- "${STAGING}/" "${SSH_USER}@${SSH_HOST}:${REPO_PATH}/"

echo "Done."
