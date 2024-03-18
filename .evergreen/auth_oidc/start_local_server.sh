#!/usr/bin/env bash
#
# Bootstrapping file to launch a local oidc-enabled server and create
# OIDC tokens that can be used for local testing.  See README for
# prerequisites and usage.
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh
ENTRYPOINT=${ENTRYPOINT:-/root/docker_entry.sh}
USE_TTY=""
DOCKER_ARG=${DOCKER_ARG:-"-i"}
VOL="-v ${DRIVERS_TOOLS}:/root/drivers-evergreen-tools"
AWS_PROFILE=${AWS_PROFILE:-""}
OIDC_TYPE=${1:-single}
ENV="-e OIDC_TYPE=$OIDC_TYPE"

if [[ "$OIDC_TYPE" != "single" ]] && [[ "$OIDC_TYPE" != "multi" ]]; then
    echo "Optional OIDC_TYPE arg must be one of 'single,multi'"
    exit 1
fi

if [ -z "$AWS_PROFILE" ]; then
    if [[ -z "${AWS_SESSION_TOKEN:-}" ||  -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
        echo "Please set AWS_PROFILE or set AWS credentials environment variables" 1>&2
       exit 1
    fi
    ENV="$ENV -e AWS_SESSION_TOKEN=$AWS_SESSION_TOKEN -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID"
    ENV="$ENV -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY"
else
    ENV="$ENV -e AWS_PROFILE=$AWS_PROFILE"
    VOL="$VOL -v $HOME/.aws:/root/.aws"
fi

rm -rf $DRIVERS_TOOLS/.evergreen/auth_oidc/authoidcvenv
test -t 1 && USE_TTY="-t"

echo "Drivers tools: $DRIVERS_TOOLS"
pushd ../docker
rm -rf ./ubuntu20.04/mongodb
echo "Building base image..."
docker build -t drivers-evergreen-tools ./ubuntu20.04
echo "Building base image... done."
popd
echo "Building oidc image..."
docker build -t oidc-test .
echo "Building oidc image... done."
echo "Running docker..."
if [[ "$OIDC_TYPE" == "single" ]]; then
    PORT=27017
else
    PORT=27018
fi
ARGS="--rm $DOCKER_ARG $USE_TTY $VOL $ENV -p $PORT:$PORT oidc-test $ENTRYPOINT"
echo "Running docker with $ARGS"
docker run $ARGS
echo "Running docker... done."
