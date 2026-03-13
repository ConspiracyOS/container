# Containerfile — ConspiracyOS base image
# Runs with systemd as PID 1. Default base: ubuntu:24.04.
# Override at build time: --build-arg BASE_IMAGE=debian:12
#
# Build: make image [BASE_IMAGE=debian:12] [PROFILE=default] [ARCH=amd64]
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

# Prevent interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# Static dependencies (design doc Section 17)
# Note: all packages below are in 'main' — no universe repo needed
RUN apt-get update && apt-get install -y \
    systemd systemd-sysv \
    openssh-server sudo git tmux curl jq \
    nftables acl unzip tree cron ca-certificates \
    auditd nginx \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/nginx/sites-enabled/default \
    && systemctl disable nginx

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Install conctl binary (pre-built via: make image, or supplied as CONCTL_BIN)
# PicoClaw agent runtime is imported as a Go library — no separate binary needed
# CI provides conctl-linux-{amd64,arm64}; local builds provide a single "conctl" file.
ARG TARGETARCH
COPY conctl* /tmp/conctl-candidates/
RUN if [ -f /tmp/conctl-candidates/conctl-linux-${TARGETARCH} ]; then \
      cp /tmp/conctl-candidates/conctl-linux-${TARGETARCH} /usr/local/bin/conctl; \
    else \
      cp /tmp/conctl-candidates/conctl /usr/local/bin/conctl; \
    fi && \
    chmod +x /usr/local/bin/conctl && \
    rm -rf /tmp/conctl-candidates

# Config profile: override at build time with --build-arg PROFILE=default
ARG PROFILE=minimal
COPY configs/${PROFILE}/ /etc/conos/

# Status page generator (runs after each healthcheck)
COPY scripts/conos-status-page.sh /usr/local/bin/conos-status-page
RUN chmod +x /usr/local/bin/conos-status-page

# Bootstrap entrypoint (runs as systemd oneshot after boot)
COPY scripts/conos-bootstrap-entry.sh /usr/local/bin/conos-bootstrap-entry
RUN chmod +x /usr/local/bin/conos-bootstrap-entry

# Env export: extract CONOS_* vars from PID 1 on every boot (before agents start)
# systemd services don't inherit the container's environment, so we write it to a file
COPY scripts/conos-export-env.sh /usr/local/bin/conos-export-env
RUN chmod +x /usr/local/bin/conos-export-env && \
    printf '[Unit]\nDescription=ConspiracyOS env export\nDefaultDependencies=no\nBefore=conos-bootstrap.service\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/conos-export-env\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/conos-env.service && \
    systemctl enable conos-env.service

# Create the bootstrap systemd unit
RUN printf '[Unit]\nDescription=ConspiracyOS Bootstrap\nAfter=network.target conos-env.service\nConditionPathExists=!/srv/conos/.bootstrapped\n\n[Service]\nType=oneshot\nExecStart=/usr/local/bin/conos-bootstrap-entry\nEnvironmentFile=-/etc/conos/env\nRemainAfterExit=yes\n\n[Install]\nWantedBy=multi-user.target\n' \
    > /etc/systemd/system/conos-bootstrap.service && \
    systemctl enable conos-bootstrap.service

# Copy test suites (smoke + e2e)
COPY test/ /test/

# SSH config (key-only auth for make apply)
RUN mkdir -p /run/sshd && \
    sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# systemd as PID 1
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
