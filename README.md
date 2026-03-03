# container — ConspiracyOS official image

The official ConspiracyOS container image. Runs Ubuntu 24.04 (or Debian 12)
with systemd as PID 1. All agent isolation is enforced by Linux — POSIX ACLs,
per-uid nftables rules, sudoers allowlists, systemd hardening.

## Build

```bash
make image
```

The build fetches the latest `conctl` binary from GitHub releases by default.
Supply a local binary during development:

```bash
make image CONCTL_BIN=/path/to/conctl
```

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BASE_IMAGE` | `ubuntu:24.04` | Base distro (`debian:12` also tested) |
| `PROFILE` | `minimal` | Config profile from `configs/` |
| `ARCH` | `arm64` | Binary architecture (`arm64` / `amd64`) |
| `RUNTIME` | `docker` | Container runtime (`docker` / `podman` / `container`) |
| `CONCTL_BIN` | — | Local conctl binary path (skips download) |
| `CONCTL_VER` | `latest` | Release tag to download if `CONCTL_BIN` not set |
| `IMAGE_NAME` | `conos` | Output image tag |

## Config profiles

Profiles live in `configs/`. Each profile is copied to `/etc/conos/` inside
the image at build time.

| Profile | Description |
|---------|-------------|
| `minimal` | Two agents: concierge + sysadmin |
| `default` | Full setup with roles, skills, contracts, and strategist officer |

## What's inside

- **systemd** as PID 1 — agents run as systemd path/service/timer units
- **`conctl`** at `/usr/local/bin/conctl` — inner runtime
- **`con-bootstrap-entry`** — systemd oneshot, runs `conctl bootstrap` on first boot
- **`con-export-env`** — extracts `CONOS_*` env vars from PID 1 before agents start
- **`con-status-page`** — regenerates `/srv/conos/status/index.html` after each healthcheck
- **Tailscale** — installed, configured via `TS_AUTHKEY` env var
- **nginx** — serves status page (disabled by default, enabled if `[dashboard]` configured)
- **auditd** — system audit logging

## Preflight

`conctl preflight` validates the image has all required capabilities.
It runs as a `RUN` layer during the build — a missing package fails the build,
not a runtime deployment.

## SSH access

SSH is enabled for `root` with key-only auth. Authorized keys are injected via
`CONOS_SSH_AUTHORIZED_KEYS` env var (newline-separated) or set in `conos.toml`.
`conos` uses SSH to run `conctl` commands on the running instance.
