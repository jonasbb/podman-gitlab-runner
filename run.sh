#!/usr/bin/env bash

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=base.sh
source "${currentDir}"/base.sh

# Workaround for bug: https://github.com/containers/libpod/issues/4326
# Based on: https://github.com/containers/libpod/issues/4326#issuecomment-572047595
# podman exec cannot read from stdin
# Therefore, we copy the file into the container and execute it from there
CMD=$(cat "$1")
if ! podman exec "$CONTAINER_ID" /bin/bash -c "$CMD"
then
    # Exit using the variable, to make the build as failure in GitLab CI.
    exit "$BUILD_FAILURE_EXIT_CODE"
fi
