# maven-ssh-deploy

Deploy Maven artifacts the opinionated Unix way - with SSH, rsync and signed tags.

- **Signed releases**: signed tags by default
- **Classical unix**: rsync over SSH
- **Fingerprint pinning**: explicit trust
- **Restricted rsync**: Use `rrsync` for peace of mind

JustWorks™ with `./mvnw` and GitHub Actions.

## Prerequisites

- **Maven wrapper** (`./mvnw`) in your project
- **Java** configured via `actions/setup-java`
- Server configured with `rrsync` (see below)

## Server Configuration

This action relies on `rrsync` (restricted rsync) on the server. The SSH keys in `~/.ssh/authorized_keys` should be configured as follows:

```
restrict,command="/usr/bin/rrsync -no-del /path/to/repo" ssh-ed25519 AAAAC3...
```

> [!IMPORTANT]
> This is the secure baseline, do not deviate unless absolutely sure!

**Note on paths:**
- If `rrsync` is used, the `path` input in the action is relative to the directory specified in the `command`.
- If `rrsync` is **not** used, the `path` to the repository most probably HAS to be specified in the action configuration.

## How It Works

1. Fetches existing `maven-metadata.xml` files from remote with rsync
2. Runs `./mvnw deploy` to a local staging directory
3. Syncs artifacts and updated metadata back to remote via rsync

## Security

- **Pull requests** are skipped by default (secrets could be exposed via PR from fork). Set `pull: true` to deploy.
- **Tag releases** require SSH signature by repository owner. Set `unsigned: true` to skip (not recommended).
- Standard repository hardening (branch protection, CODEOWNERS etc) applies.

> [!IMPORTANT]
> For the "Verified" badge on commits/tags and tag signature checks to work, add your SSH signing key at [github.com/settings/keys](https://github.com/settings/keys).

## Usage

```yaml
- uses: actions/setup-java@v5
  with:
    distribution: temurin
    java-version: 17

- uses: martinpaljak/maven-ssh-deploy@v1
  with:
    user: mvn@example.com:2222
    key: ${{ secrets.SSH_KEY }}
    host_fp: SHA256:2wykddxDwF8jXGvVvKX9ayLYF4cbKFahQgEKe5Cn26Y
```

> [!TIP]
> For best security, pin to a specific commit hash of the plugin instead of a tag.

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `user` | Yes | SSH user (can be `user@host:port`) |
| `key` | Yes | SSH private key |
| `host_fp` | Yes | SSH host fingerprint (`SHA256:...`) |
| `host` | No | SSH host (if not in `user`) |
| `path` | No | Remote path for tag releases (default: `.`) |
| `snapshots` | No | Remote path for non-tag builds (default: `SNAPSHOTS`) |
| `pull` | No | Allow pull requests (default: `false`) |
| `unsigned` | No | Skip tag signature verification (default: `false`) |

## Example Workflow

```yaml
name: Deploy
on:
  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-java@v5
        with:
          distribution: temurin
          java-version: 17
      - run: ./mvnw -B verify
      - uses: martinpaljak/maven-ssh-deploy@v1
        with:
          user: foo@example.com
          key: ${{ secrets.SSH_KEY }}
          host_fp: SHA256:auiF3nHWvDmvq2stDl+QEECCqMcDp+FY1/bDRnvxpRw
```

## Local Usage

For manual deploys from your workstation (uses system SSH config):

```bash
./deploy.sh user@maven.example.com:2222 [path]
```

## Why This Action?

### Eliminates Maven's wagon-ssh dependency

```xml
<build>
  <extensions>
    <extension>
      <groupId>org.apache.maven.wagon</groupId>
      <artifactId>wagon-ssh-external</artifactId>
      <version>3.5.3</version>
    </extension>
  </extensions>
</build>

<distributionManagement>
  <repository>
    <id>myrepo</id>
    <url>scpexe://mvn@maven.example.com/repo/</url>
  </repository>
</distributionManagement>
```

The wagon-ssh-external extension is slow, deprecated, and adds unnecessary complexity to every pom.xml. This action uses rsync instead - faster, standard, and requires zero Maven configuration. 

### Simplifies CI/CD to a single step

I used to use this before:
```yaml
- uses: webfactory/ssh-agent@v0.9.1
  with:
    ssh-private-key: ${{ secrets.SSH_KEY }}
- run: ssh-keyscan maven.example.com >> ~/.ssh/known_hosts
- run: ./mvnw deploy
```

This action consolidates everything into one focused step.
