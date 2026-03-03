#!/bin/bash
# /usr/local/bin/conos-bootstrap-entry
# Runs once on first boot to provision the conspiracy.
set -euo pipefail

echo "ConspiracyOS bootstrap starting..."

# Run the bootstrap
conctl bootstrap

# Mark as bootstrapped
touch /srv/conos/.bootstrapped

echo "ConspiracyOS bootstrap complete."
