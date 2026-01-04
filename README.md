# maven-ssh-deploy
Deploy Maven repository over SSH and rsync

## Usage

```yaml
- uses: martinpaljak/maven-ssh-deploy@v1
  with:
    user: ${{ env.SSH_USER }}
    key: ${{ secrets.SSH_KEY }}
    host_key: ${{ env.HOST_KEY }}
    path: "ephemeral-repo"
```

## Inputs

- **user** (required): SSH user for deployment
- **key** (required): SSH private key for authentication
- **host_key** (required): SSH host key for verification
- **path** (required): Path to the repository directory

## Example

```yaml
name: Deploy Maven Repository
on:
  push:
    branches: [ main ]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Deploy Maven artifacts
        uses: martinpaljak/maven-ssh-deploy@v1
        with:
          user: ${{ env.SSH_USER }}
          key: ${{ secrets.SSH_KEY }}
          host_key: ${{ env.HOST_KEY }}
          path: "ephemeral-repo"
```

## Description

This GitHub Action runs in an Alpine Linux Docker container and sets up SSH authentication for deploying Maven repositories. It configures SSH with the provided credentials and prepares the environment for deployment operations.
