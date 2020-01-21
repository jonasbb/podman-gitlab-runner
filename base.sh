# shellcheck shell=bash disable=SC2034

currentDir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Variables defined here will be availble to all the scripts.

CONTAINER_ID="runner-$CUSTOM_ENV_CI_RUNNER_ID-project-$CUSTOM_ENV_CI_PROJECT_ID-concurrent-$CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID-$CUSTOM_ENV_CI_JOB_ID"
IMAGE="$CUSTOM_ENV_CI_JOB_IMAGE"
CACHE_DIR="$(dirname "${BASH_SOURCE[0]}")/../_cache/runner-$CUSTOM_ENV_CI_RUNNER_ID-project-$CUSTOM_ENV_CI_PROJECT_ID-concurrent-$CUSTOM_ENV_CI_CONCURRENT_PROJECT_ID"

# Execute customization code
if [ -f "${currentDir}"/custom_base.sh ]; then
    # shellcheck source=custom_base.sh disable=SC1091
    source "${currentDir}"/custom_base.sh
fi
