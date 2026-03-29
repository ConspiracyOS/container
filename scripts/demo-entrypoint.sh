#!/bin/bash
# demo-entrypoint.sh — Boot ConspiracyOS and run the self-healing demo.
#
# This entrypoint:
# 1. Starts systemd (PID 1) in background
# 2. Waits for bootstrap to complete
# 3. Runs the self-healing demo
#
# Usage (from Containerfile.demo):
#   CMD ["/usr/local/bin/demo-entrypoint"]
#
# Pass --dry-run to skip sysadmin LLM execution:
#   docker run --rm -it --privileged ghcr.io/conspiracyos/conos-demo --dry-run

set -euo pipefail

DEMO_ARGS="${*}"

echo "ConspiracyOS Demo — booting..."

# Start systemd as PID 1 (required for systemctl, nftables, etc.)
/sbin/init &
INIT_PID=$!

# Wait for systemd to be ready
for i in $(seq 1 30); do
    if systemctl is-system-running --wait 2>/dev/null | grep -qE 'running|degraded'; then
        break
    fi
    sleep 1
done

# Wait for bootstrap to complete
for i in $(seq 1 60); do
    if [ -f /srv/conos/.bootstrapped ]; then
        break
    fi
    sleep 1
done

if [ ! -f /srv/conos/.bootstrapped ]; then
    echo "ERROR: Bootstrap did not complete within 60 seconds."
    echo "Check: journalctl -u conos-bootstrap.service"
    exit 1
fi

echo "Bootstrap complete. Starting demo..."
echo ""

# Run the demo
exec /usr/local/bin/demo-self-healing $DEMO_ARGS
