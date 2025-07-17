#!/bin/bash
source /usr/bin/logger.sh

RUNNER_ASSETS_DIR=${RUNNER_ASSETS_DIR:-/runnertmp}
RUNNER_HOME=${RUNNER_HOME:-/home/runner}

# Export hooks for GitHub Runner
export ACTIONS_RUNNER_HOOK_JOB_STARTED=/etc/arc/hooks/job-started.sh
export ACTIONS_RUNNER_HOOK_JOB_COMPLETED=/etc/arc/hooks/job-completed.sh

# Startup delay if needed
if [ -n "${STARTUP_DELAY_IN_SECONDS}" ]; then
  log.notice "Delaying startup by ${STARTUP_DELAY_IN_SECONDS} seconds"
  sleep "${STARTUP_DELAY_IN_SECONDS}"
fi

# Validate GitHub URL
if [ -z "${GITHUB_URL}" ]; then
  log.debug 'Working with public GitHub'
  GITHUB_URL="https://github.com/"
else
  length=${#GITHUB_URL}
  last_char=${GITHUB_URL:length-1:1}
  [[ $last_char != "/" ]] && GITHUB_URL="$GITHUB_URL/"; :
  log.debug "Github endpoint URL ${GITHUB_URL}"
fi

# Validate required parameters
if [ -z "${RUNNER_NAME}" ]; then
  log.error 'RUNNER_NAME must be set'
  exit 1
fi

if [ -z "${RUNNER_TOKEN}" ]; then
  log.error 'RUNNER_TOKEN must be set'
  exit 1
fi

# Configure attachment point
ATTACH=""
if [ -n "${RUNNER_ORG}" ] && [ -n "${RUNNER_REPO}" ]; then
  ATTACH="${RUNNER_ORG}/${RUNNER_REPO}"
elif [ -n "${RUNNER_ORG}" ]; then
  ATTACH="${RUNNER_ORG}"
elif [ -n "${RUNNER_REPO}" ]; then
  ATTACH="${RUNNER_REPO}"
elif [ -n "${RUNNER_ENTERPRISE}" ]; then
  ATTACH="enterprises/${RUNNER_ENTERPRISE}"
else
  log.error 'At least one of RUNNER_ORG, RUNNER_REPO, or RUNNER_ENTERPRISE must be set'
  exit 1
fi

# Validate runner home directory
if [ ! -d "${RUNNER_HOME}" ]; then
  log.error "RUNNER_HOME directory ${RUNNER_HOME} does not exist"
  exit 1
fi

# Copy runner assets
if [[ "${UNITTEST:-}" == '' ]]; then
  log.debug "Copying runner assets to ${RUNNER_HOME}"
  shopt -s dotglob
  cp -r "$RUNNER_ASSETS_DIR"/* "$RUNNER_HOME"/
  shopt -u dotglob

  # Fix permissions for OpenShift
  chmod -R g+rw "$RUNNER_HOME"
fi

# Change to runner home
if ! cd "${RUNNER_HOME}"; then
  log.error "Failed to cd into ${RUNNER_HOME}"
  exit 1
fi

# Prepare config arguments
config_args=()
[ "${RUNNER_EPHEMERAL}" == "true" ] && config_args+=(--ephemeral)
[ "${DISABLE_RUNNER_UPDATE}" == "true" ] && config_args+=(--disableupdate)

# Configure runner
update-status "Registering"
log.notice "Configuring GitHub runner"

retries=10
while [[ $retries -gt 0 ]]; do
  ./config.sh --unattended --replace \
    --name "${RUNNER_NAME}" \
    --url "${GITHUB_URL}${ATTACH}" \
    --token "${RUNNER_TOKEN}" \
    --runnergroup "${RUNNER_GROUPS}" \
    --labels "${RUNNER_LABELS}" \
    --work "${RUNNER_WORKDIR}" "${config_args[@]}"

  if [ -f .runner ]; then
    log.debug 'Runner successfully configured'
    break
  fi

  log.debug "Configuration failed, retries left: $((retries-1))"
  sleep 1
  retries=$((retries-1))
done

if [ ! -f .runner ]; then
  log.error 'Runner configuration failed!'
  exit 2
fi

# Move externals if needed
if [ -z "${UNITTEST:-}" ] && [ -e ./externalstmp ]; then
  mkdir -p ./externals
  mv ./externalstmp/* ./externals/
fi

# Wait for Docker if enabled
if [[ "${DOCKER_ENABLED}" == "true" ]] && [[ "${DISABLE_WAIT_FOR_DOCKER}" != "true" ]]; then
  WAIT_TIMEOUT=${WAIT_FOR_DOCKER_SECONDS:-120}
  log.debug "Waiting for Docker daemon (timeout: ${WAIT_TIMEOUT}s)"

  if ! timeout "${WAIT_TIMEOUT}s" bash -c 'until docker info >/dev/null 2>&1; do sleep 1; done'; then
    log.error "Docker daemon not available after ${WAIT_TIMEOUT} seconds"
    exit 3
  fi
  log.debug "Docker daemon is available"
fi

# Clean up sensitive env vars
unset RUNNER_NAME RUNNER_TOKEN RUNNER_ORG RUNNER_REPO RUNNER_ENTERPRISE

# Start the runner
update-status "Idle"
log.notice "Starting runner listener"
exec ./run.sh
