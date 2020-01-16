#!/usr/bin/env bash

TMPDIR=$(pwd)

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=base.sh
source "${currentDir}"/base.sh

echo "Deleting container $CONTAINER_ID"

podman kill "$CONTAINER_ID"
podman rm "$CONTAINER_ID"

# Delete leftover files in /tmp
rm -r "$TMPDIR"

exit 0
