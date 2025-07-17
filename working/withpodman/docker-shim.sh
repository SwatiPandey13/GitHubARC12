#!/usr/bin/env bash

set -Eeuo pipefail

PODMAN=/usr/bin/podman
#if [ ! -e $DOCKER ]; then
#  DOCKER=/home/runner/bin/docker
#fi

if [[ ${ARC_DOCKER_MTU_PROPAGATION:-false} == true ]] &&
  (($# >= 2)) && [[ $1 == network && $2 == create ]] &&
  mtu=$($PODMAN network inspect podman --format '{{index .Options "mtu"}}' 2>/dev/null); then
  shift 2
  set -- network create --opt mtu="$mtu" "$@"
fi

exec $PODMAN "$@"
