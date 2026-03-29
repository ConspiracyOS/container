#!/bin/bash
# demo-self-healing.sh — Demonstrate the self-healing immune system loop.
#
# This script:
# 1. Breaks a specific contract (removes immutable bit from critical files)
# 2. Triggers the healthcheck (detects the violation)
# 3. Shows the escalation task in sysadmin's inbox
# 4. Runs the sysadmin agent (remediates the violation)
# 5. Triggers healthcheck again (verifies the fix)
# 6. Prints a timeline of the entire loop
#
# Requirements:
# - Must run inside a ConspiracyOS container/instance
# - conctl must be in PATH
# - sysadmin agent must be provisioned with LLM access
#
# Usage:
#   ./demo-self-healing.sh           # full demo with sysadmin agent
#   ./demo-self-healing.sh --dry-run # show escalation only, skip sysadmin execution

set -euo pipefail

DRY_RUN=false
[ "${1:-}" = "--dry-run" ] && DRY_RUN=true

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

timestamp() { date '+%H:%M:%S'; }

echo ""
echo "============================================"
echo "  ConspiracyOS Self-Healing Immune System"
echo "============================================"
echo ""

SYSADMIN_INBOX="/srv/conos/agents/sysadmin/inbox"
TARGET_FILE="/etc/conos/conos.toml"

# Verify we're in a ConspiracyOS environment
if ! command -v conctl >/dev/null 2>&1; then
    echo -e "${RED}ERROR: conctl not found. Run this inside a ConspiracyOS instance.${NC}"
    exit 1
fi

if [ ! -d "$SYSADMIN_INBOX" ]; then
    echo -e "${RED}ERROR: Sysadmin inbox not found at $SYSADMIN_INBOX${NC}"
    exit 1
fi

# Step 0: Verify the contract currently passes
echo -e "${BLUE}[$(timestamp)] Step 0: Verify CON-SEC-005 currently passes${NC}"
if conctl healthcheck 2>/dev/null; then
    echo -e "${GREEN}  All contracts passing.${NC}"
else
    echo -e "${YELLOW}  Some contracts already failing. Proceeding anyway.${NC}"
fi
echo ""

# Clear any existing escalation tasks for a clean demo
EXISTING=$(find "$SYSADMIN_INBOX" -name '*healthcheck.task' 2>/dev/null | wc -l)
if [ "$EXISTING" -gt 0 ]; then
    echo -e "${YELLOW}  Clearing $EXISTING existing escalation tasks for clean demo.${NC}"
    find "$SYSADMIN_INBOX" -name '*healthcheck.task' -delete 2>/dev/null || true
fi

T_START=$(date +%s)

# Step 1: Break the contract
echo -e "${RED}[$(timestamp)] Step 1: INJECTING FAULT — removing immutable bit from $TARGET_FILE${NC}"
chattr -i "$TARGET_FILE" 2>/dev/null || {
    echo -e "${YELLOW}  File was not immutable (or chattr not available). Setting it first...${NC}"
    chattr +i "$TARGET_FILE" 2>/dev/null || true
    chattr -i "$TARGET_FILE" 2>/dev/null || {
        echo -e "${RED}  Cannot modify immutable bit. Are you root?${NC}"
        exit 1
    }
}
echo -e "  ${RED}Immutable bit removed. CON-SEC-005 will now fail.${NC}"
T_INJECT=$(date +%s)
echo ""

# Step 2: Trigger healthcheck
echo -e "${BLUE}[$(timestamp)] Step 2: Running healthcheck (contract evaluation)${NC}"
conctl healthcheck 2>&1 | while IFS= read -r line; do
    echo "  $line"
done || true
T_DETECT=$(date +%s)
echo ""

# Step 3: Show escalation task
echo -e "${BLUE}[$(timestamp)] Step 3: Checking sysadmin inbox for escalation task${NC}"
TASK_COUNT=$(find "$SYSADMIN_INBOX" -name '*healthcheck.task' 2>/dev/null | wc -l)
if [ "$TASK_COUNT" -gt 0 ]; then
    echo -e "  ${GREEN}Found $TASK_COUNT escalation task(s):${NC}"
    for task in "$SYSADMIN_INBOX"/*healthcheck.task; do
        [ -f "$task" ] || continue
        echo -e "  ${YELLOW}--- $(basename "$task") ---${NC}"
        cat "$task" | sed 's/^/    /'
        echo ""
    done
else
    echo -e "  ${RED}No escalation tasks found. The escalation may have failed.${NC}"
    echo -e "  ${YELLOW}Check: ls $SYSADMIN_INBOX${NC}"
fi
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[$(timestamp)] --dry-run: Skipping sysadmin execution.${NC}"
    echo ""
    echo -e "${YELLOW}To complete the demo manually:${NC}"
    echo "  1. Run: conctl run sysadmin"
    echo "  2. Then: conctl healthcheck"
    echo "  3. Verify CON-SEC-005 passes"
    exit 0
fi

# Step 4: Run sysadmin agent
echo -e "${BLUE}[$(timestamp)] Step 4: Running sysadmin agent (LLM-mediated remediation)${NC}"
echo -e "  ${YELLOW}Sysadmin will read the escalation task and execute remediation...${NC}"
if conctl run sysadmin 2>&1 | while IFS= read -r line; do
    echo "  $line"
done; then
    echo -e "  ${GREEN}Sysadmin completed.${NC}"
else
    echo -e "  ${RED}Sysadmin execution failed or returned non-zero.${NC}"
fi
T_REMEDIATE=$(date +%s)
echo ""

# Step 5: Verify the fix
echo -e "${BLUE}[$(timestamp)] Step 5: Re-running healthcheck (verification)${NC}"
if conctl healthcheck 2>&1 | while IFS= read -r line; do
    echo "  $line"
done; then
    echo -e "  ${GREEN}All contracts passing. System healed.${NC}"
    HEALED=true
else
    echo -e "  ${RED}Some contracts still failing. Remediation may be incomplete.${NC}"
    HEALED=false
fi
T_VERIFY=$(date +%s)
echo ""

# Step 6: Timeline
echo "============================================"
echo "  Timeline"
echo "============================================"
echo ""
printf "  %-20s %s\n" "Fault injected:" "+$((T_INJECT - T_START))s"
printf "  %-20s %s\n" "Violation detected:" "+$((T_DETECT - T_START))s"
printf "  %-20s %s\n" "Remediation done:" "+$((T_REMEDIATE - T_START))s"
printf "  %-20s %s\n" "Verification:" "+$((T_VERIFY - T_START))s"
printf "  %-20s %s\n" "Total loop time:" "$((T_VERIFY - T_START))s"
echo ""
if [ "$HEALED" = true ]; then
    echo -e "  ${GREEN}RESULT: HEALED — full detect-contain-remediate-verify loop completed.${NC}"
else
    echo -e "  ${RED}RESULT: PARTIAL — remediation did not fully resolve the violation.${NC}"
    echo -e "  ${YELLOW}Check sysadmin outbox: ls /srv/conos/agents/sysadmin/outbox/${NC}"
fi
echo ""
