#!/usr/bin/env bash

# Rename this file to `custom_base.sh`!
#
# The file contains examples how the different variables can be used.

# Pass additional arguments to `podman run` in `prepare.sh`.
# Mount additional volumes into the container or limit the CPU utilization.
# PODMAN_RUN_ARGS[0]='--volume=/mnt:/path/in/container:z'
# PODMAN_RUN_ARGS[1]='--cpus=1'

# Change the command given to `podman run` in `prepare.sh`.
# This command *must* not return or the container could stop before the
# tasks are done. The default is to call `sleep` with a very long time.
# PODMAN_RUN_COMMAND=/sbin/init
