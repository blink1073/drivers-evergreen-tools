#!/usr/bin/env bash
# DRIVERS-3712 verification helpers for the MongoDB Cloud Tag Policy.
#
# Source this file and call the functions with a description and the JSON
# returned by the corresponding API/CLI call. Each function echoes the JSON
# for evidence, then exits non-zero if the mongodb-owner or mongodb-env value
# is missing or empty. The checks use python3 (stdlib json) rather than jq,
# which is not installed on every drivers distro (e.g. debian11).
#
# Gate the calls on VERIFY_MONGODB_TAGS, mirroring
# .evergreen/aws_lambda/run-deployed-lambda-aws-tests.sh.

# Checks a tags map, as returned by the aws/az CLIs, e.g.
#   {"mongodb-owner": "...", "mongodb-env": "dev"}
# If an object key is given (e.g. "labels" or "resourceLabels"), the map is
# read from that key of the passed object instead - used for gcloud's
# `--format json(labels)` output and the like.
verify_cloud_tags ()
{
  local description=$1
  local tags=$2
  local key=${3:-}
  echo "verify-tags: ${description} tags: ${tags}"
  if ! python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if sys.argv[2]:
    data = data.get(sys.argv[2]) if isinstance(data, dict) else None
if not isinstance(data, dict) or not data.get("mongodb-owner") or not data.get("mongodb-env"):
    sys.exit(1)
' "${tags}" "${key}" > /dev/null; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}

# Checks a tags array, as returned by the Atlas API, e.g.
#   [{"key": "mongodb-owner", "value": "..."}, {"key": "mongodb-env", ...}]
verify_atlas_tags ()
{
  local description=$1
  local tags=$2
  echo "verify-tags: ${description} tags: ${tags}"
  if ! python3 -c '
import json, sys
try:
    data = json.loads(sys.argv[1])
except ValueError:
    sys.exit(1)
if not isinstance(data, list):
    sys.exit(1)
values = {t.get("key"): t.get("value") for t in data if isinstance(t, dict)}
if not values.get("mongodb-owner") or not values.get("mongodb-env"):
    sys.exit(1)
' "${tags}" > /dev/null; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}
