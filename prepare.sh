#!/usr/bin/env bash

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
# shellcheck source=base.sh
source "${currentDir}"/base.sh

set -eEo pipefail

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

    # Try logging into the Gitlab Registry if credentials are provided
    # https://docs.gitlab.com/ee/user/packages/container_registry/index.html#authenticate-by-using-gitlab-cicd
    if ! podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" --get-login "$CUSTOM_ENV_CI_REGISTRY" 2>/dev/null && \
        [[ -n "$CUSTOM_ENV_CI_DEPLOY_USER" && -n "$CUSTOM_ENV_CI_DEPLOY_PASSWORD" ]]
    then
        echo "Login to ${CUSTOM_ENV_CI_REGISTRY} with CI_DEPLOY_USER"
        podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" \
            --username "$CUSTOM_ENV_CI_DEPLOY_USER" \
            --password "$CUSTOM_ENV_CI_DEPLOY_PASSWORD" \
            "$CUSTOM_ENV_CI_REGISTRY"
    fi

    if ! podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" --get-login "$CUSTOM_ENV_CI_REGISTRY" 2>/dev/null && \
        [[ -n "$CUSTOM_ENV_CI_JOB_USER" && -n "$CUSTOM_ENV_CI_JOB_TOKEN" ]]
    then
        echo "Login to ${CUSTOM_ENV_CI_REGISTRY} with CI_JOB_USER"
        podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" \
            --username "$CUSTOM_ENV_CI_JOB_USER" \
            --password "$CUSTOM_ENV_CI_JOB_TOKEN" \
            "$CUSTOM_ENV_CI_REGISTRY"
    fi

    if ! podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" --get-login "$CUSTOM_ENV_CI_REGISTRY" 2>/dev/null && \
        [[ -n "$CUSTOM_ENV_CI_REGISTRY_USER" && -n "$CUSTOM_ENV_CI_REGISTRY_PASSWORD" ]]
    then
        echo "Login to ${CUSTOM_ENV_CI_REGISTRY} with CI_REGISTRY_USER"
        podman login --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" \
            --username "$CUSTOM_ENV_CI_REGISTRY_USER" \
            --password "$CUSTOM_ENV_CI_REGISTRY_PASSWORD" \
            "$CUSTOM_ENV_CI_REGISTRY"
    fi

    podman pull --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" "$IMAGE"
    rm "$CACHE_DIR"/_authfile_"$CONTAINER_ID"
    podman run \
        --detach \
        --name "$CONTAINER_ID" \
        --volume "$CACHE_DIR:/home/user/cache":Z \
        "${PODMAN_RUN_ARGS[@]}" \
        "$IMAGE"\
        sleep 999999999
}

install_command() {
    # Run test if this binary exists
    PACKAGE=$1
    TEST_BINARY=$PACKAGE

    podman exec --user root:root "$CONTAINER_ID" /bin/bash -c 'if ! type '"$TEST_BINARY"' >/dev/null 2>&1; then
        if type apt-get >/dev/null 2>&1; then
            echo "APT based distro without '"$TEST_BINARY"'"
            apt-get update && apt-get install --no-install-recommends --yes '"$PACKAGE"'
        elif type dnf >/dev/null 2>&1; then
            echo "DNF based distro without '"$TEST_BINARY"'"
            dnf install --setopt=install_weak_deps=False --assumeyes '"$PACKAGE"'
        elif type apk >/dev/null 2>&1; then
            echo "APK based distro without '"$TEST_BINARY"'"
            apk add '"$PACKAGE"'
        elif type yum >/dev/null 2>&1; then
            echo "YUM based distro without '"$TEST_BINARY"'"
            yum install --assumeyes '"$PACKAGE"'
        elif type pacman >/dev/null 2>&1; then
            echo "PACMAN based distro without '"$TEST_BINARY"'"
            pacman --sync --refresh --noconfirm '"$PACKAGE"'
        elif type zypper >/dev/null 2>&1; then
            echo "ZYPPER based distro without '"$TEST_BINARY"'"
            zypper install --no-confirm --no-recommends '"$PACKAGE"'
        fi
    fi'
}

install_dependencies() {
    # Copy gitlab-runner binary from the server into the container
    if [ -x /usr/local/bin/gitlab-runner ]; then
        podman cp --pause=false /usr/local/bin/gitlab-runner "$CONTAINER_ID":/usr/bin/gitlab-runner
    else
        podman cp --pause=false /usr/bin/gitlab-runner "$CONTAINER_ID":/usr/bin/gitlab-runner
    fi

    # Install bash in systems with APK (e.g., Alpine)
    podman exec --user root:root "$CONTAINER_ID" sh -c 'if ! type bash >/dev/null 2>&1 && type apk >/dev/null 2>&1 ; then echo "APK based distro without bash"; apk add bash; fi'

    install_command ca-certificates
    install_command git
    # Not available on all systems, e.g., Debian 9 or RHEL 7
    install_command git-lfs || true
}

echo "Running in $CONTAINER_ID"

start_container
install_dependencies
