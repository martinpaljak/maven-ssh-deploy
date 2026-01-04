#!/bin/bash
set -e

# Get inputs from environment variables set by GitHub Actions
SSH_USER="${INPUT_USER}"
SSH_KEY="${INPUT_KEY}"
HOST_KEY="${INPUT_HOST_KEY}"
REPO_PATH="${INPUT_PATH}"

echo "Setting up SSH configuration..."

# Create SSH directory
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Set up SSH private key
printf '%s\n' "${SSH_KEY}" > ~/.ssh/id_rsa
chmod 600 ~/.ssh/id_rsa

# Set up known_hosts with the host key
echo "${HOST_KEY}" > ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts

# Create SSH config
cat > ~/.ssh/config << EOF
Host *
    StrictHostKeyChecking yes
    UserKnownHostsFile ~/.ssh/known_hosts
EOF
chmod 600 ~/.ssh/config

echo "SSH configuration complete."

# Find Maven repository in the workspace
if [ -z "${REPO_PATH}" ]; then
    echo "Error: path parameter is required"
    exit 1
fi

# Check if the path exists in the workspace
if [ ! -d "${GITHUB_WORKSPACE}/${REPO_PATH}" ]; then
    echo "Error: Repository path ${GITHUB_WORKSPACE}/${REPO_PATH} does not exist"
    exit 1
fi

echo "Deploying Maven repository from ${REPO_PATH}..."

# Get the target from the path directory (assuming it contains deployment info)
# This is a placeholder - actual deployment logic would depend on your requirements
cd "${GITHUB_WORKSPACE}/${REPO_PATH}"

# Example: Deploy using rsync (adjust as needed for your use case)
# rsync -avz -e ssh ./ ${SSH_USER}@<target-host>:/path/to/destination/

echo "Deployment preparation complete."
echo "Repository path: ${GITHUB_WORKSPACE}/${REPO_PATH}"

# Add actual deployment commands here based on your specific needs
# For now, this script sets up the SSH environment and validates inputs

exit 0
