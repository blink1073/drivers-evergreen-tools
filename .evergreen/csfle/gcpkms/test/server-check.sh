#!/usr/bin/env bash
#
# Check the server the gcpkms setup group started.
#
# setup.sh has already provisioned the instance and run start-mongodb.sh, which
# runs run-orchestration.sh, so this only has to prove the server answers and that
# it came from this revision.
set -o errexit
set -o pipefail
set -o nounset

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../../../handle-paths.sh"
pushd "$SCRIPT_DIR/.." > /dev/null

# setup.sh wrote the instance name and the gcloud path here.
# shellcheck source=/dev/null
source ./secrets-export.sh

# start-mongodb.sh clones when the archive is missing, and a clone would leave
# this variant testing master. The archive ships no .git, a clone leaves one.
# Each remote command takes </dev/null because gcloud compute ssh reads stdin.
if ! GCPKMS_CMD='[ ! -d ./drivers-evergreen-tools/.git ]' ./run-command.sh < /dev/null; then
  echo "ERROR: the instance cloned drivers-evergreen-tools instead of unpacking the archive." >&2
  echo "It is running the default branch, so this run does not test this revision." >&2
  exit 1
fi

# On the legacy variant, check the instance really has no pip; carried by the
# exit status because run-command.sh echoes the command it runs.
if [ "${kms_legacy_provisioning:-}" = "true" ]; then
  if ! GCPKMS_CMD='if python3 -m pip --version; then exit 17; fi' ./run-command.sh < /dev/null; then
    echo "ERROR: the instance has pip, so this run did not exercise the venv fallback." >&2
    echo "Has remote-scripts/legacy/setup-gce-instance.sh drifted, or the base image changed?" >&2
    exit 1
  fi
fi

# A successful ping here is also the only proof that the venv-fallback ensure_uv
# took above actually produced a working uv: nothing here calls uv directly.
GCPKMS_CMD='./drivers-evergreen-tools/mongodb/bin/mongosh --quiet --eval "db.runCommand({ping:1})" mongodb://localhost:27017' \
  ./run-command.sh < /dev/null

popd > /dev/null
