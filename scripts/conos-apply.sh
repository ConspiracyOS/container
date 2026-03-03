#!/bin/bash
# Apply a config profile to a running container via container exec.
# Usage: conos-apply.sh <profile> <container-name>
set -euo pipefail

PROFILE="$1"
NAME="$2"
SRC="configs/${PROFILE}"

find "$SRC" -type f | while IFS= read -r f; do
    rel="${f#${SRC}/}"
    dir="$(dirname "$rel")"
    container exec "$NAME" mkdir -p "/etc/conos/${dir}"

    # Write file content via heredoc (container exec stdin piping is unreliable)
    content="$(cat "$f")"
    container exec "$NAME" bash -c "cat > '/etc/conos/${rel}' << 'CONEOF'
${content}
CONEOF"

    # Preserve execute bit from source
    if [ -x "$f" ]; then
        container exec "$NAME" chmod +x "/etc/conos/${rel}"
    fi
    echo "  + /etc/conos/${rel}"
done

echo "Running bootstrap..."
container exec "$NAME" bash -c 'set -a; . /etc/conos/env 2>/dev/null; set +a; conctl bootstrap'
echo "Profile ${PROFILE} applied to ${NAME}."
