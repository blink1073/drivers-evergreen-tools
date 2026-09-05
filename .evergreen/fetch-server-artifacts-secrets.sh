#!/usr/bin/env bash
# Fetch DRIVERS_TEST_SECRETS_ROLE_ARN and SERVER_ARTIFACTS_SECRET_VAULT from
# the drivers/devprod-release-infrastructure vault, needed to download an
# unpublished "latest"/"latest-build" server binary from the private S3
# bucket. Requires AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY/AWS_SESSION_TOKEN
# for drivers_test_secrets_role to already be in the environment.
#
# Writes the two values to server-artifacts-expansion.yml so a caller can
# promote them to Evergreen expansions with `expansions.update`. Requires
# bash (setup-secrets.sh uses bash-only syntax), unlike run-orchestration.sh.
set -eu

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
OUT_FILE="server-artifacts-expansion.yml"
: > "$OUT_FILE"

case "${MONGODB_VERSION:-latest}" in
  latest | latest-build)
    . "$SCRIPT_DIR/secrets_handling/setup-secrets.sh" drivers/devprod-release-infrastructure
    echo "DRIVERS_TEST_SECRETS_ROLE_ARN: \"$DRIVERS_TEST_SECRETS_ROLE_ARN\"" >>"$OUT_FILE"
    echo "SERVER_ARTIFACTS_SECRET_VAULT: \"$SERVER_ARTIFACTS_SECRET_VAULT\"" >>"$OUT_FILE"
    ;;
esac
