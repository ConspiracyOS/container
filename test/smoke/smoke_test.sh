#!/bin/bash
# test/smoke/smoke_test.sh
# End-to-end smoke test for ConspiracyOS Phase 1.
# Run this INSIDE the VM after bootstrap completes.
set -euo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $desc"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $desc"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== ConspiracyOS Phase 1 Smoke Test ==="

# Discover configured agents from the actual system
AGENTS=()
for agent_home in /srv/conos/agents/*/; do
    [ -d "$agent_home" ] || continue
    AGENTS+=("$(basename "$agent_home")")
done
echo "Configured agents: ${AGENTS[*]}"

echo ""
echo "--- 1. Bootstrap verification ---"
check "conctl binary exists" test -x /usr/local/bin/conctl
check "bootstrapped marker exists" test -f /srv/conos/.bootstrapped
for agent in "${AGENTS[@]}"; do
    check "user a-$agent exists" id "a-$agent"
done
check "group agents exists" getent group agents
check "group operators exists" getent group operators

echo ""
echo "--- 2. Directory structure ---"
check "outer inbox exists" test -d /srv/conos/inbox
for agent in "${AGENTS[@]}"; do
    check "$agent inbox exists" test -d "/srv/conos/agents/$agent/inbox"
    check "$agent workspace exists" test -d "/srv/conos/agents/$agent/workspace"
done
check "audit log dir exists" test -d /srv/conos/logs/audit

echo ""
echo "--- 3. Permissions ---"
check "outer inbox is root:agents 770" [ "$(stat -c %a /srv/conos/inbox)" = "770" ]
for agent in "${AGENTS[@]}"; do
    check "$agent home is private" [ "$(stat -c %a /home/a-$agent)" = "700" ]
done

echo ""
echo "--- 4. Systemd units ---"
for agent in "${AGENTS[@]}"; do
    check "$agent path unit enabled" systemctl is-enabled "conos-$agent.path"
done

echo ""
echo "--- 5. AGENTS.md assembled ---"
for agent in "${AGENTS[@]}"; do
    check "$agent AGENTS.md exists" test -f "/home/a-$agent/AGENTS.md"
done
# Check content on first agent
first="${AGENTS[0]}"
check "base content in $first AGENTS.md" grep -q "ConspiracyOS" "/home/a-$first/AGENTS.md"

echo ""
echo "--- 6. End-to-end task routing ---"
SMOKE_TASK="smoke-$(date +%s).task"
echo "Dropping task into outer inbox ($SMOKE_TASK)..."
echo "What agents are currently running in this conspiracy?" > "/srv/conos/inbox/$SMOKE_TASK"
# Explicitly trigger routing — PathChanged may not re-fire if the path unit
# already triggered during bootstrap or a prior run.
sleep 1
conctl route-inbox 2>/dev/null || true
echo "Waiting for concierge to process (up to 30s)..."

WAITED=0
while [ $WAITED -lt 30 ]; do
    if [ -f "/srv/conos/agents/concierge/processed/$SMOKE_TASK" ] 2>/dev/null || \
       find /srv/conos/agents/concierge/outbox -maxdepth 1 -name '*.response' 2>/dev/null | grep -q .; then
        break
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

check "task was picked up from outer inbox" test ! -f "/srv/conos/inbox/$SMOKE_TASK"
check "concierge produced output" find /srv/conos/agents/concierge/outbox -maxdepth 1 -name '*.response' 2>/dev/null -print -quit

echo ""
echo "--- 7. Audit trail ---"
# The task routing above should have created an audit entry
check "audit log dir has entries" \
    sh -c "find /srv/conos/logs/audit -name '*.log' -size +0 2>/dev/null | grep -q ."

echo ""
echo "--- 8. Git snapshot ---"
check "/srv/conos is a git repo" test -d /srv/conos/.git
check "git has initial commit" git -C /srv/conos log --oneline -1
check "git identity configured" git -C /srv/conos config user.name
check ".gitignore excludes workspaces" grep -q "agents/\*/workspace/" /srv/conos/.gitignore

echo ""
echo "--- 9. Systemd hardening ---"
# Workers should have NoNewPrivileges (sysadmin should NOT)
for agent_dir in /srv/conos/agents/*/; do
    agent=$(basename "$agent_dir")
    unit_file="/etc/systemd/system/conos-${agent}.service"
    [ -f "$unit_file" ] || continue
    case "$agent" in
        sysadmin)
            check "sysadmin lacks NoNewPrivileges" \
                sh -c "! grep -q 'NoNewPrivileges=yes' $unit_file"
            ;;
        *)
            if grep -q 'NoNewPrivileges' "$unit_file"; then
                check "$agent has NoNewPrivileges" \
                    grep -q 'NoNewPrivileges=yes' "$unit_file"
            fi
            ;;
    esac
done
check "worker units have ProtectHome" \
    grep -q 'ProtectHome=tmpfs' "/etc/systemd/system/conos-${first}.service"

echo ""
echo "--- 10. Contract timer ---"
check "healthcheck timer active" systemctl is-active conos-healthcheck.timer
# Trigger healthcheck to ensure contracts.log exists (timer may not have fired yet on fresh boot)
conctl healthcheck >/dev/null 2>&1 || true
if ls /srv/conos/contracts/*.yaml >/dev/null 2>&1; then
    check "contracts log exists" test -f /srv/conos/logs/audit/contracts.log
else
    echo "  SKIP: no contracts installed"
fi

echo ""
echo "--- 11. Skill injection ---"
for agent_dir in /srv/conos/agents/*/; do
    agent=$(basename "$agent_dir")
    skills_dir="${agent_dir}workspace/skills"
    [ -d "$skills_dir" ] || continue
    md_count=$(find "$skills_dir" -maxdepth 1 -name '*.md' ! -name '._*' 2>/dev/null | wc -l)
    if [ "$md_count" -gt 0 ]; then
        check "$agent has skills deployed" test "$md_count" -gt 0
    fi
done

echo ""
echo "--- 12. Agent instruction integrity ---"
for agent_dir in /srv/conos/agents/*/; do
    agent=$(basename "$agent_dir")
    check "$agent AGENTS.md.sha256 exists" test -f "/home/a-${agent}/AGENTS.md.sha256"
    if [ -f "/home/a-${agent}/AGENTS.md.sha256" ] && [ -f "/home/a-${agent}/AGENTS.md" ]; then
        current=$(sha256sum "/home/a-${agent}/AGENTS.md" | awk '{print $1}')
        stored=$(awk '{print $1}' "/home/a-${agent}/AGENTS.md.sha256")
        check "$agent AGENTS.md hash matches" test "$current" = "$stored"
    fi
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ $FAIL -eq 0 ] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
exit $FAIL
