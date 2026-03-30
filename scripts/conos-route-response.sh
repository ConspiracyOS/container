#!/bin/bash
# conos-route-response: Post-run routing for agent responses.
# Parses the latest response from the calling agent for routing directives
# and delivers the task content to the target agent's inbox.
#
# Usage: conos-route-response <agent-name>
# Runs as ExecStartPost=+ (root) on agent service units.

set -euo pipefail

AGENT="${1:?Usage: conos-route-response <agent-name>}"
AGENTS_DIR="/srv/conos/agents"
OUTBOX="${AGENTS_DIR}/${AGENT}/outbox"
PROCESSED="${AGENTS_DIR}/${AGENT}/processed"
LOG="/srv/conos/logs/audit/$(date +%Y-%m-%d).log"

# Discover valid agent names from filesystem (not hardcoded)
KNOWN_AGENTS=""
for d in "${AGENTS_DIR}"/*/inbox; do
    [ -d "$d" ] || continue
    name=$(basename "$(dirname "$d")")
    [ "$name" = "$AGENT" ] && continue  # skip self
    KNOWN_AGENTS="${KNOWN_AGENTS} ${name}"
done

# Find the most recent response
latest=$(find "$OUTBOX" -name "*.response" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -z "$latest" ] && exit 0

response=$(cat "$latest")

# Extract target agent from response.
# Matches: "-> qa-hub", "route to worker-hub", "ROUTE_TO: manager",
#           "assign to sysadmin", "deliver to qa-rs"
target=""
for agent in $KNOWN_AGENTS; do
    if echo "$response" | grep -qiE "(->|route[d]?\s+to|routing\s+to|deliver\s+to|forward\s+to|assign(ed)?\s+to|submit\s+to|ROUTE_TO:?)\s*(the\s+)?${agent}"; then
        target="$agent"
        break
    fi
done

[ -z "$target" ] && exit 0

# Find the corresponding processed task (most recent)
task_file=$(find "$PROCESSED" -name "*.task" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
[ -z "$task_file" ] && exit 0

# Deliver to target agent's inbox
ts=$(date -u +%Y%m%dT%H%M%SZ)
dest="${AGENTS_DIR}/${target}/inbox/${ts}-from-${AGENT}.task"

# Include the response as the task content (not the original task)
# so the target agent sees what the source agent produced.
cat > "$dest" << TASKEOF
${response}
TASKEOF

chown "a-${target}:agents" "$dest" 2>/dev/null || true
chmod 640 "$dest" 2>/dev/null || true

echo "$(date -Iseconds) [route] ${AGENT} -> ${target}: $(basename "$task_file") -> $(basename "$dest")" >> "$LOG"
