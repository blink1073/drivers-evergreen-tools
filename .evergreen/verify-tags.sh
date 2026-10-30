#!/usr/bin/env bash
# DRIVERS-3712 verification helpers for the MongoDB Cloud Tag Policy.
#
# Source this file and call the functions with a description and the JSON
# returned by the corresponding API/CLI call. Each function echoes the JSON
# for evidence, then exits non-zero if the mongodb-owner or mongodb-env value
# is missing or empty. Gate the calls on VERIFY_MONGODB_TAGS, mirroring
# .evergreen/aws_lambda/run-deployed-lambda-aws-tests.sh.

# Expects a tags map, as returned by the aws/az/gcloud CLIs, e.g.
#   {"mongodb-owner": "...", "mongodb-env": "dev"}
verify_cloud_tags ()
{
  local description=$1
  local tags=$2
  echo "verify-tags: ${description} tags: ${tags}"
  if ! jq -e '(.["mongodb-owner"] // "" | length > 0) and (.["mongodb-env"] // "" | length > 0)' > /dev/null <<< "${tags}"; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}

# Expects a tags array, as returned by the Atlas API, e.g.
#   [{"key": "mongodb-owner", "value": "..."}, {"key": "mongodb-env", ...}]
verify_atlas_tags ()
{
  local description=$1
  local tags=$2
  echo "verify-tags: ${description} tags: ${tags}"
  if ! jq -e 'any(.[]; .key == "mongodb-owner" and .value != "") and any(.[]; .key == "mongodb-env" and .value != "")' > /dev/null <<< "${tags}"; then
    echo "verify-tags FAILED: ${description} lacks mongodb-owner/mongodb-env tags" 1>&2
    exit 1
  fi
  echo "verify-tags OK: ${description} carries mongodb-owner/mongodb-env"
}
