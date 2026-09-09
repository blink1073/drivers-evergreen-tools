#!/usr/bin/env bash
#
# Asserts .evergreen/docker/run-server.sh forwards the host's AWS identity into
# the container by name, and mounts the AWS config only when AWS_PROFILE is set.
#
set -eu

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

make_stub() {
  local work="$1"
  mkdir -p "$work/dt/.evergreen/orchestration"
  touch "$work/dt/.gitignore"
  # run-server.sh runs setup.sh after the run to restore the CLIs; stub it out.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$work/dt/.evergreen/orchestration/setup.sh"
  chmod +x "$work/dt/.evergreen/orchestration/setup.sh"

  cat > "$work/docker" <<'DOCKER'
#!/usr/bin/env bash
if [ "${1:-}" = "run" ]; then
  printf '%s ' "$@" > "${DOCKER_RUN_ARGS_FILE:?}"
fi
exit 0
DOCKER
  chmod +x "$work/docker"
}

assert_contains() {
  local file="$1" needle="$2"
  if ! grep -qF "$needle" "$file"; then
    echo "  FAIL: docker run args are missing '$needle':" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_absent() {
  local file="$1" needle="$2"
  if grep -qF "$needle" "$file"; then
    echo "  FAIL: docker run args unexpectedly contain '$needle':" >&2
    cat "$file" >&2
    exit 1
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
make_stub "$work"

# Unset any ambient AWS identity so it cannot influence the checks.
run_server() {
  local args_file="$1"
  shift
  env -u CI \
    -u AWS_PROFILE \
    -u AWS_ACCESS_KEY_ID \
    -u AWS_SECRET_ACCESS_KEY \
    -u AWS_SESSION_TOKEN \
    DOCKER_COMMAND="$work/docker" \
    DOCKER_RUN_ARGS_FILE="$args_file" \
    DRIVERS_TOOLS="$work/dt" \
    MONGODB_VERSION=8.0 \
    "$@" \
    bash "$ROOT_DIR/docker/run-server.sh" > /dev/null
}

# All four variables are forwarded by name; no mount without AWS_PROFILE.
run_server "$work/no-profile-args"
for var in AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_PROFILE; do
  assert_contains "$work/no-profile-args" "$var"
done
assert_absent "$work/no-profile-args" "/root/.aws:ro"

# With AWS_PROFILE the config directory is mounted read-only.
run_server "$work/profile-args" AWS_PROFILE=test-profile
assert_contains "$work/profile-args" "AWS_PROFILE"
assert_contains "$work/profile-args" "/root/.aws:ro"

echo "AWS forwarding checks passed."
