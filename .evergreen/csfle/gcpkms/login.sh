#!/usr/bin/env bash

set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/../../handle-paths.sh

if [ -f $SCRIPT_DIR/secrets-export.sh ]; then
  echo "Sourcing secrets"
  source $SCRIPT_DIR/secrets-export.sh
fi

# Write the keyfile content to a local JSON path.
if [ -n "${GCPKMS_KEYFILE_CONTENT:-}" ]; then
    export GCPKMS_KEYFILE=/tmp/testgcpkms_key_file.json
    # convert content from base64 to JSON and write to file
    echo ${GCPKMS_KEYFILE_CONTENT} | base64 --decode > $GCPKMS_KEYFILE
fi

if [ -z "$GCPKMS_KEYFILE" ]; then
    echo "Please set the following required environment variables"
    echo " GCPKMS_KEYFILE to the JSON file for the service account"
    exit 1
fi

# Set 600 permissions on private key file. Otherwise ssh / scp may error with permissions "are too open".
chmod 600 $GCPKMS_KEYFILE

gcloud auth activate-service-account --key-file $GCPKMS_KEYFILE
