#!/bin/bash
# test/e2e/31-immutable-files.sh
# Verify that critical files have immutable bit set after bootstrap,
# and that agents cannot modify them.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 31: Immutable Critical Files ==="

echo ""
echo "--- 1. Immutable bit on config files ---"
check "conos.toml is immutable" \
    sh -c "lsattr /etc/conos/conos.toml 2>/dev/null | grep -q '^....i'"
check "env file is immutable" \
    sh -c "lsattr /etc/conos/env 2>/dev/null | grep -q '^....i'"
check "artifact signing key is immutable" \
    sh -c "lsattr /etc/conos/artifact-signing.key 2>/dev/null | grep -q '^....i'"
check "conctl binary is immutable" \
    sh -c "lsattr /usr/local/bin/conctl 2>/dev/null | grep -q '^....i'"

echo ""
echo "--- 2. Immutable bit on sudoers ---"
for f in /etc/sudoers.d/conos-*; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    check "$name is immutable" \
        sh -c "lsattr '$f' 2>/dev/null | grep -q '^....i'"
done

echo ""
echo "--- 3. Immutable bit on systemd units ---"
found_unit=false
for f in /etc/systemd/system/conos-*; do
    [ -f "$f" ] || continue
    found_unit=true
    name=$(basename "$f")
    check "$name is immutable" \
        sh -c "lsattr '$f' 2>/dev/null | grep -q '^....i'"
done
$found_unit || echo "  SKIP: no conos-* systemd units found"

echo ""
echo "--- 4. Agent cannot modify immutable files ---"
# Try to write to conos.toml as concierge — should fail
check_fail "concierge cannot write to conos.toml" \
    su -s /bin/sh a-concierge -c "echo test >> /etc/conos/conos.toml"

# Try to remove the immutable bit as concierge — should fail (no capability)
check_fail "concierge cannot chattr -i conos.toml" \
    su -s /bin/sh a-concierge -c "chattr -i /etc/conos/conos.toml"

echo ""
echo "--- 5. WithMutable pattern works for root ---"
# Root can temporarily clear immutable, write, re-apply
chattr -i /etc/conos/conos.toml 2>/dev/null
check "root can clear immutable bit" \
    sh -c "lsattr /etc/conos/conos.toml 2>/dev/null | grep -qv '^....i'"
chattr +i /etc/conos/conos.toml 2>/dev/null
check "root can re-apply immutable bit" \
    sh -c "lsattr /etc/conos/conos.toml 2>/dev/null | grep -q '^....i'"

echo ""
echo "--- 6. Auditd watches active ---"
if auditctl -l >/dev/null 2>&1; then
    check "auditd watching /etc/conos" \
        sh -c "auditctl -l | grep -q conos_config_tamper"
    check "auditd watching /etc/sudoers.d" \
        sh -c "auditctl -l | grep -q conos_sudoers_tamper"
    check "auditd watching systemd units" \
        sh -c "auditctl -l | grep -q conos_systemd_tamper"
    check "auditd watching conctl binary" \
        sh -c "auditctl -l | grep -q conos_binary_tamper"
else
    echo "  SKIP: auditd not available (Docker/container environment)"
fi

finish
