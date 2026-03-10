#!/bin/bash
# test/e2e/35-contract-execution.sh
# Verify detective contracts CON-SEC-001 and CON-SEC-005 catch violations.
# Tests T-012 from the threat register.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 35: Contract Execution (T-012) ==="

CONTRACTS_DIR="/srv/conos/contracts"

# Install contracts if not present
for contract in CON-SEC-001 CON-SEC-005; do
    if [ ! -f "$CONTRACTS_DIR/${contract}.yaml" ]; then
        cp "/etc/conos/contracts/${contract}.yaml" "$CONTRACTS_DIR/" 2>/dev/null || true
    fi
done

# Create CON-SEC-001 inline if still missing
if [ ! -f "$CONTRACTS_DIR/CON-SEC-001.yaml" ]; then
    cat > "$CONTRACTS_DIR/CON-SEC-001.yaml" << 'YAML'
id: CON-SEC-001
description: Skills and agent instruction files must be owned by root
type: detective
tags: [schedule]
scope: global
checks:
  - name: skills_root_owned
    script:
      inline: |
        found=$(find /etc/conos/roles /etc/conos/agents -name '*.md' ! -user root 2>/dev/null)
        if [ -n "$found" ]; then
          echo "Non-root-owned skill files found:"
          echo "$found"
          exit 1
        fi
    on_fail: escalate
    severity: critical
    category: security
    what: "Skills or agent instruction files not owned by root"
YAML
fi

# Create CON-SEC-005 inline if still missing
if [ ! -f "$CONTRACTS_DIR/CON-SEC-005.yaml" ]; then
    cat > "$CONTRACTS_DIR/CON-SEC-005.yaml" << 'YAML'
id: CON-SEC-005
description: Critical configuration files must have immutable bit set
type: detective
tags: [schedule]
scope: global
checks:
  - name: config_immutable
    script:
      inline: |
        fail=0
        for f in /etc/conos/conos.toml /etc/conos/env /usr/local/bin/conctl; do
          [ -f "$f" ] || continue
          if ! lsattr "$f" 2>/dev/null | grep -q '^....i'; then
            echo "NOT IMMUTABLE: $f"
            fail=1
          fi
        done
        exit $fail
    on_fail: escalate
    severity: critical
    category: security
    what: "Critical file missing immutable bit"
YAML
fi

echo ""
echo "--- 1. CON-SEC-001: Skills root-owned (clean state) ---"
# Healthcheck logs status like "CON-SEC-001 PASS/WARN skills_root_owned"
output=$(conctl healthcheck 2>&1 || true)
check "CON-SEC-001 passes in clean state" \
    sh -c "echo '$output' | grep -q 'CON-SEC-001 PASS'"

echo ""
echo "--- 2. CON-SEC-001: Detect non-root skill file ---"
# Create a skill owned by concierge agent (violation)
mkdir -p /etc/conos/roles/test-role/skills
echo "# test skill" > /etc/conos/roles/test-role/skills/test.md
chown a-concierge:agents /etc/conos/roles/test-role/skills/test.md
output=$(conctl healthcheck 2>&1 || true)
check "CON-SEC-001 detects non-root skill" \
    sh -c "echo '$output' | grep -q 'CON-SEC-001 FAIL'"
# Fix it
chown root:root /etc/conos/roles/test-role/skills/test.md
rm -rf /etc/conos/roles/test-role

echo ""
echo "--- 3. CON-SEC-005: Immutable bits (clean state) ---"
output=$(conctl healthcheck 2>&1 || true)
check "CON-SEC-005 passes in clean state" \
    sh -c "echo '$output' | grep -q 'CON-SEC-005 PASS'"

echo ""
echo "--- 4. CON-SEC-005: Detect removed immutable bit ---"
# Temporarily remove immutable bit from conos.toml
chattr -i /etc/conos/conos.toml 2>/dev/null
output=$(conctl healthcheck 2>&1 || true)
check "CON-SEC-005 detects missing immutable bit" \
    sh -c "echo '$output' | grep -q 'CON-SEC-005 FAIL'"
# Restore
chattr +i /etc/conos/conos.toml 2>/dev/null

echo ""
echo "--- 5. Healthcheck runs all contracts without crash ---"
check "healthcheck exits cleanly" \
    conctl healthcheck

finish
