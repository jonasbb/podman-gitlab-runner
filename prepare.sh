#!/usr/bin/env bash

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=base.sh
source "${currentDir}"/base.sh

set -eo pipefail

# trap any error, and mark it as a system failure.
trap 'exit $SYSTEM_FAILURE_EXIT_CODE' ERR

start_container() {
    if podman inspect "$CONTAINER_ID" >/dev/null 2>&1; then
        echo 'Found old container, deleting'
        podman kill "$CONTAINER_ID"
        podman rm "$CONTAINER_ID"
    fi

    mkdir -p "$CACHE_DIR"
    # Use value of ENV variable or {} as empty settings
    echo "${CUSTOM_ENV_DOCKER_AUTH_CONFIG:-{\}}" > "$CACHE_DIR"/_authfile_"$CONTAINER_ID"
    podman pull --authfile="$CACHE_DIR"/_authfile_"$CONTAINER_ID" "$IMAGE"
    rm "$CACHE_DIR"/_authfile_"$CONTAINER_ID"
    podman run \
        --detach \
        --interactive \
        --tty \
        --name "$CONTAINER_ID" \
        --volume "$CACHE_DIR:/home/user/cache":Z \
        "${PODMAN_RUN_ARGS[@]}" \
        "$IMAGE"
}

install_dependencies() {
    # Install gitlab-runner binary since we need for cache/artifacts.
    curl -L --output gitlab-runner-"$CONTAINER_ID" https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-amd64
    chmod +x gitlab-runner-"$CONTAINER_ID"
    podman cp --pause=false gitlab-runner-"$CONTAINER_ID" "$CONTAINER_ID":/usr/bin/gitlab-runner
    rm gitlab-runner-"$CONTAINER_ID"

    # Install bash in systems with APK (e.g., Alpine)
    podman exec "$CONTAINER_ID" sh -c 'if ! type bash >/dev/null 2>&1 && type apk >/dev/null 2>&1 ; then echo "APK based distro without bash"; apk add bash; fi'

    # Install git in systems with APT (e.g., Debian)
    podman exec "$CONTAINER_ID" /bin/bash -c 'if ! type git >/dev/null 2>&1 && type apt-get >/dev/null 2>&1 ; then echo "APT based distro without git"; apt-get update && apt-get install --no-install-recommends -y ca-certificates git; fi'
    # Install git in systems with DNF (e.g., Fedora)
    podman exec "$CONTAINER_ID" /bin/bash -c 'if ! type git >/dev/null 2>&1 && type dnf >/dev/null 2>&1 ; then echo "DNF based distro without git"; dnf install --setopt=install_weak_deps=False --assumeyes git; fi'
    # Install git in systems with APK (e.g., Alpine)
    podman exec "$CONTAINER_ID" /bin/bash -c 'if ! type git >/dev/null 2>&1 && type apk >/dev/null 2>&1 ; then echo "APK based distro without git"; apk add git; fi'
}

echo "Running in $CONTAINER_ID"

start_container
install_dependencies
