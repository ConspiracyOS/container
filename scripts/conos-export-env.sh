#!/bin/sh
# Extract CONOS_* environment variables from PID 1 (container runtime)
# and write them to /etc/conos/env for systemd services.
# Runs on every boot before other ConspiracyOS services.
#
# Mode 600 root:root — only root (systemd PID 1) can read.
# Agents receive env vars via systemd EnvironmentFile= injection,
# never by reading the file directly. This prevents any agent from
# reading secrets belonging to other agents.
tr '\0' '\n' < /proc/1/environ | grep -E '^(CONOS_|TS_)' > /etc/conos/env 2>/dev/null
chmod 600 /etc/conos/env
chown root:root /etc/conos/env
