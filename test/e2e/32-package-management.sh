#!/bin/bash
# test/e2e/32-package-management.sh
# Verify conctl package install/remove/list.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 32: Package Management ==="

echo ""
echo "--- 1. Package install ---"
# Use bc — small, available in base Ubuntu repos
apt-get remove -y bc >/dev/null 2>&1 || true
check "install bc for concierge" \
    conctl package install bc --agent concierge
check "bc binary exists after install" \
    which bc
check "audit log records install" \
    grep -q "package:install.*bc.*agent=concierge" /srv/conos/logs/audit/package.log

echo ""
echo "--- 2. Package name validation ---"
check_fail "reject invalid package name" \
    conctl package install "../etc/passwd" --agent concierge
check_fail "reject empty agent" \
    conctl package install bc

echo ""
echo "--- 3. Package list ---"
# --save to persist, then list
conctl package install bc --agent concierge --save >/dev/null 2>&1 || true
output=$(conctl package list --agent concierge 2>&1)
check "list shows bc for concierge" \
    echo "$output" | grep -q "bc"

echo ""
echo "--- 4. Package remove ---"
check "remove bc" \
    conctl package remove bc --agent concierge
check "audit log records removal" \
    grep -q "package:remove.*bc" /srv/conos/logs/audit/package.log

echo ""
echo "--- 5. Package install with --save handles immutable config ---"
# Config is immutable — --save should still work (uses WithMutable)
check "conos.toml is immutable before --save" \
    sh -c "lsattr /etc/conos/conos.toml 2>/dev/null | grep -q '^....i'"
conctl package install bc --agent concierge --save >/dev/null 2>&1
check "conos.toml is still immutable after --save" \
    sh -c "lsattr /etc/conos/conos.toml 2>/dev/null | grep -q '^....i'"
check "bc appears in config" \
    grep -q "bc" /etc/conos/conos.toml

# Clean up
conctl package remove bc --agent concierge --save >/dev/null 2>&1 || true

finish
