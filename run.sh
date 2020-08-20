#!/usr/bin/env bash

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=base.sh
source "${currentDir}"/base.sh

if ! podman exec "$CONTAINER_ID" /bin/bash < "$1"
then
    # Exit using the variable, to make the build as failure in GitLab CI.
    exit "$BUILD_FAILURE_EXIT_CODE"
fi
