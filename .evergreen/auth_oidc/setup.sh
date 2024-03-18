#!/usr/bin/env bash

set -o errexit

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../handle-paths.sh

pushd $SCRIPT_DIR
bash ./oidc_get_tokens.sh

await_server() {
    echo "Waiting on $1 server on port $2"
    for i in $(seq 20); do
        if curl -s "localhost:$2"; test $? -eq 0; then
            echo "Waiting on $1 server on port $2...done"
            return 0
        else
            echo "Could not connect, sleeping."
            sleep 10
        fi
    done
    echo "Could not detect '$1' server on port $2"
    exit 1
}

source ./secrets-export.sh
echo "export OIDC_URI_MULTI=$OIDC_ATLAS_URI_MULTI" >> secrets-export.sh

# If on Windows or there is no docker, use Atlas cluster for single.
if [[ "${OSTYPE:?}" == cygwin ]] || [[ ! $(command -v docker 2>&1 /dev/null) ]]; then
    echo "export OIDC_URI_SINGLE=$OIDC_ATLAS_URI_SINGLE" >> secrets-export.sh

# Otherwise use local cluster from docker.
else
    DOCKER_ARG="-di" bash ./start_local_server.sh
    echo 'export OIDC_URI_SINGLE="mongodb://localhost:27017"' >> secrets-export.sh
    await_server "MongoDB" 27017
fi
