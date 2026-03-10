#!/bin/bash
# test/e2e/34-git-remote-audit.sh
# Verify CON-SEC-002: agent git repos must not have unauthorized remotes.
# Tests T-011 from the threat register.
set -euo pipefail
source "$(dirname "$0")/helpers.sh"

echo "=== E2E Test 34: Git Remote Audit (T-011) ==="

CONTRACTS_DIR="/srv/conos/contracts"
AGENT_DIR="/srv/conos/agents/concierge/workspace"

# Install the contract if not present
if [ ! -f "$CONTRACTS_DIR/CON-SEC-002.yaml" ]; then
    cp /etc/conos/contracts/CON-SEC-002.yaml "$CONTRACTS_DIR/" 2>/dev/null || \
    cat > "$CONTRACTS_DIR/CON-SEC-002.yaml" << 'YAML'
id: CON-SEC-002
description: Agent git repositories must not have unauthorized remote destinations
type: detective
tags: [schedule]
scope: global
checks:
  - name: git_remotes_audit
    script:
      inline: |
        fail=0
        for gitdir in $(find /srv/conos/agents -maxdepth 4 -name '.git' -type d 2>/dev/null); do
          repo=$(dirname "$gitdir")
          for url in $(git -C "$repo" remote -v 2>/dev/null | awk '/\(fetch\)/{print $2}'); do
            case "$url" in
              *github.com/ConspiracyOS/*|http://localhost*|git://localhost*|file://*)
                ;;
              *)
                echo "Unauthorized git remote in $repo: $url"
                fail=1
                ;;
            esac
          done
        done
        exit $fail
    on_fail: alert
    severity: critical
    category: security
    what: "Agent git repository has unauthorized remote destination"
YAML
fi

echo ""
echo "--- 1. No repos = clean pass ---"
# Remove any stale git repos in agent workspace
rm -rf "$AGENT_DIR/test-repo" 2>/dev/null || true
output=$(conctl healthcheck 2>&1 || true)
# Healthcheck logs status lines like "CON-SEC-002 PASS/WARN git_remotes_audit"
check "no repos passes healthcheck" \
    sh -c "! echo '$output' | grep -q 'CON-SEC-002 WARN'"

echo ""
echo "--- 2. Authorized remote passes ---"
mkdir -p "$AGENT_DIR/test-repo"
cd "$AGENT_DIR/test-repo"
git init -q
git remote add origin https://github.com/ConspiracyOS/conctl.git
cd /
output=$(conctl healthcheck 2>&1 || true)
check "authorized remote passes" \
    sh -c "! echo '$output' | grep -q 'CON-SEC-002 WARN'"

echo ""
echo "--- 3. Unauthorized remote detected ---"
cd "$AGENT_DIR/test-repo"
git remote add evil https://github.com/attacker/exfil.git
cd /
output=$(conctl healthcheck 2>&1 || true)
check "unauthorized remote detected" \
    sh -c "echo '$output' | grep -q 'CON-SEC-002 WARN'"

echo ""
echo "--- 4. Localhost remote is allowed ---"
cd "$AGENT_DIR/test-repo"
git remote remove evil
git remote add local http://localhost:3000/repo.git
cd /
output=$(conctl healthcheck 2>&1 || true)
check "localhost remote passes" \
    sh -c "! echo '$output' | grep -q 'CON-SEC-002 WARN'"

# Clean up
rm -rf "$AGENT_DIR/test-repo"

finish
