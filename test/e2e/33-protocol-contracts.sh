#!/bin/bash
# test/e2e/33-protocol-contracts.sh
# Verify conctl protocol check/list with protocol contracts.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 33: Protocol Contracts ==="

CONTRACTS_DIR="/srv/conos/contracts"

echo ""
echo "--- 1. Create a test protocol contract ---"
cat > "$CONTRACTS_DIR/CON-PROTO-TEST.yaml" << 'YAML'
id: CON-PROTO-TEST
description: Test protocol contract
type: protocol
trigger: "test action"
checks:
  - name: always_pass
    command:
      run: "true"
      exit_code: 0
    on_fail: halt
    severity: critical
    what: "This check always passes"
  - name: always_fail
    command:
      run: "false"
      exit_code: 0
    on_fail: halt
    severity: critical
    what: "This check always fails"
YAML
check "test protocol contract created" test -f "$CONTRACTS_DIR/CON-PROTO-TEST.yaml"

echo ""
echo "--- 2. Protocol check detects halt ---"
# Should exit 1 because always_fail halts
check_fail "protocol check blocks on failing check" \
    conctl protocol check CON-PROTO-TEST
# Verify output mentions HALT
output=$(conctl protocol check CON-PROTO-TEST 2>&1 || true)
check "output shows HALT status" \
    sh -c "echo '$output' | grep -q HALT"
check "output shows BLOCKED message" \
    sh -c "echo '$output' | grep -q BLOCKED"

echo ""
echo "--- 3. Protocol check with exemption ---"
output=$(conctl protocol check CON-PROTO-TEST --exempt always_fail --reason "testing" 2>&1 || true)
check "exemption clears the halt" \
    sh -c "echo '$output' | grep -q OK"
check "exemption logged to audit" \
    grep -q "protocol:exempt.*CON-PROTO-TEST/always_fail" /srv/conos/logs/audit/protocol.log

echo ""
echo "--- 4. Protocol list ---"
output=$(conctl protocol list 2>&1)
check "protocol list includes test contract" \
    sh -c "echo '$output' | grep -q CON-PROTO-TEST"
check "protocol list shows trigger" \
    sh -c "echo '$output' | grep -q 'test action'"

echo ""
echo "--- 5. Type mismatch warning ---"
# Run protocol check on a non-protocol contract (if any exist)
detective=$(find "$CONTRACTS_DIR" -name '*.yaml' -exec grep -l 'type: detective' {} + 2>/dev/null | head -1 || true)
if [ -n "$detective" ]; then
    det_id=$(grep '^id:' "$detective" | awk '{print $2}')
    output=$(conctl protocol check "$det_id" 2>&1 || true)
    check "warns on non-protocol contract" \
        sh -c "echo '$output' | grep -qi 'warning.*not.*protocol'"
else
    echo "  SKIP: no detective contracts to test type warning"
fi

echo ""
echo "--- 6. Contract ID before flags (flag parsing fix) ---"
# This tests fix #7: contract ID can appear before --exempt/--reason
output=$(conctl protocol check CON-PROTO-TEST --exempt always_fail --reason "flag-order-test" 2>&1 || true)
check "ID before flags works" \
    sh -c "echo '$output' | grep -q OK"

# Clean up
rm -f "$CONTRACTS_DIR/CON-PROTO-TEST.yaml"
rm -f /srv/conos/logs/audit/protocol.log

finish
