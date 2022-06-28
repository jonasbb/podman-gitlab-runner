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
    if [[ -n "$CUSTOM_ENV_CI_REGISTRY" ]]
    then
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
    fi

    podman pull --authfile "$CACHE_DIR"/_authfile_"$CONTAINER_ID" "$IMAGE"
    rm "$CACHE_DIR"/_authfile_"$CONTAINER_ID"
    # We want shell splitting on PODMAN_RUN_COMMAND
    # shellcheck disable=2086
    podman run \
        --detach \
        --name "$CONTAINER_ID" \
        --volume "$CACHE_DIR:/home/user/cache":z \
        "${PODMAN_RUN_ARGS[@]}" \
        "$IMAGE"\
        ${PODMAN_RUN_COMMAND:-sleep 999999999}
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
    local RUNNER_BINARY
    local RUNNER_BINARY_PREFIX
    local RUNNER_BINARY_TMP

    # First check some predefined paths
    for RUNNER_BINARY_PREFIX in /usr{/local,}/bin
    do
      RUNNER_BINARY="${RUNNER_BINARY_PREFIX}/gitlab-runner"
      if [ -x "${RUNNER_BINARY}" ]
      then
        break
      fi
    done

    # If unsuccessful, check shell PATHs
    if [ ! -x "${RUNNER_BINARY}" ]
    then
      RUNNER_BINARY="$(type -p gitlab-runner || true)"
    fi

    # As a last resort, download binary...
    if [ ! -x "${RUNNER_BINARY}" ]
    then
      # ... to temporary directory
      RUNNER_BINARY_TMP="$(mktemp --directory --tmpdir="${CACHE_DIR}")"
      RUNNER_BINARY="${RUNNER_BINARY_TMP}/gitlab-runner"

      # Find local architecture to download correct binary
      # https://stackoverflow.com/questions/45125516/possible-values-for-uname-m/45125525#45125525
      local RUNNER_BINARY_ARCH
      local RUNNER_BINARY_URL
      case "$(uname -m)" in
        x86_64)
          RUNNER_BINARY_ARCH=amd64
          ;;
        arm)
          RUNNER_BINARY_ARCH=arm
          ;;
        i[36]86)
          RUNNER_BINARY_ARCH=386
          ;;
        aarch64|armv8l)
          RUNNER_BINARY_ARCH=arm64
          ;;
        s390*)
          RUNNER_BINARY_ARCH=s390x
          ;;
        ppc64le)
          RUNNER_BINARY_ARCH=ppc64le
          ;;
      esac
      # https://docs.gitlab.com/runner/install/linux-manually.html#install-1
      RUNNER_BINARY_URL="https://gitlab-runner-downloads.s3.amazonaws.com/latest/binaries/gitlab-runner-linux-${RUNNER_BINARY_ARCH}"

      # Errors during download should kill the script...
      curl --location --output "${RUNNER_BINARY}" "${RUNNER_BINARY_URL}"
      # ... otherwise, we now have a working gitlab-runner binary
      chmod +x "${RUNNER_BINARY}"
    fi

    podman cp --pause=false "${RUNNER_BINARY}" "$CONTAINER_ID":/usr/bin/gitlab-runner

    # Clean up if download directory was used
    if [ -d "${RUNNER_BINARY_TMP}" ]
    then
      rm -rf "${RUNNER_BINARY_TMP}"
    fi

    # Install bash in systems with APK (e.g., Alpine)
    podman exec --user root:root "$CONTAINER_ID" sh -c 'if ! type bash >/dev/null 2>&1 && type apk >/dev/null 2>&1 ; then echo "APK based distro without bash"; apk add bash; fi'

    install_command hostname
    install_command ca-certificates
    install_command git
    # Not available on all systems, e.g., Debian 9 or RHEL 7
    install_command git-lfs || true
}

echo "Running in $CONTAINER_ID"

start_container
install_dependencies

# Create build folder such that unprivileged users have access
podman exec --user root:root "$CONTAINER_ID" /bin/bash -c "mkdir -p '$CUSTOM_ENV_CI_BUILDS_DIR' && chmod -R 777 '$CUSTOM_ENV_CI_BUILDS_DIR'"
