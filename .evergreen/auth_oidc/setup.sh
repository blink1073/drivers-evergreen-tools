#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR
bash ./oidc_get_tokens.sh

source ./secrets-export.sh
echo "export OIDC_URI_MULTI=$OIDC_ATLAS_URI_MULTI" >> secrets-export.sh

# If on Windows or there is no docker, use Atlas cluster for single.
if [[ "${OSTYPE:?}" == cygwin ]] || [[ ! $(command -v docker 2>&1 /dev/null) ]]; then
    echo "export OIDC_URI_SINGLE=$OIDC_ATLAS_URI_SINGLE" >> secrets-export.sh
    echo "export OIDC_ADMIN_USER=$OIDC_ALTAS_USER" >> secrets-export.sh
    echo "export OIDC_ADMIN_PASSWORD=$OIDC_ATLAS_PASSWORD" >> secrets-export.sh

# Otherwise use local cluster from docker.
else
    rm -f $DRIVERS_TOOLS/server.log
    DOCKER_ARG="-di" bash ./start_local_server.sh
    echo 'export OIDC_URI_SINGLE="mongodb://localhost:27017"' >> secrets-export.sh
    echo "export OIDC_ADMIN_USER=bob" >> secrets-export.sh
    echo "export OIDC_ADMIN_PASSWORD=pwd123" >> secrets-export.sh
    echo "Waiting for orchestration to start..."
    while [ ! -f $DRIVERS_TOOLS/server.log ]; do sleep 1; done
    echo "Waiting for orchestration to start... done."
    echo "Waiting for server to start..."
    grep -q 'send_result' <(tail -f $DRIVERS_TOOLS/server.log)
    echo "Waiting for server to start... done."
    cat $DRIVERS_TOOLS/server.log
fi
