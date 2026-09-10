#!/usr/bin/env bash
#
# Regression tests for the ensure_uv install paths that no image or VM in the
# current matrix reproduces. The KMS variants cover a host with both pip and
# venv, and the kms-legacy variant covers a venv-only host without pip; these
# two shapes cover the other two corners, and neither needs a cloud VM or a
# container:
#   - ensure_uv called from inside an active virtual environment. pip is present
#     but refuses --user, so uv has to be installed into the active venv.
#   - ensure_uv on a host with pip but no working venv module, where pip is the
#     only way through.
# Each runs in a private HOME/TMPDIR so the install cannot leak anywhere, and
# skips on hosts that cannot reproduce the shape.
set -eu -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

# The container suite this replaces ran on Linux only, and the venv/PATH
# handling this test relies on differs on Git-Bash. The KMS variables it covers
# are equally Unix-only, so keep it that way.
if [ "$(uname -s)" != "Darwin" ] && [ "$(uname -s)" != "Linux" ]; then
  echo "test-ensure-uv.sh: only runs on Linux and macOS; skipping."
  make -C "$DRIVERS_TOOLS" test
  exit 0
fi

# Setting up the shapes needs a python3 that can build a venv and one with pip.
# Some small CI images (e.g. RHEL) ship neither, so skip rather than fail.
if ! python3 -m venv --help >/dev/null 2>&1 || ! python3 -m pip --version >/dev/null 2>&1; then
  echo "test-ensure-uv.sh: python3-venv and python3-pip not available; skipping."
  make -C "$DRIVERS_TOOLS" test
  exit 0
fi

ENSURE_UV="$SCRIPT_DIR/../ensure-uv.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ensure-uv-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# Running ensure_uv with the repo's DRIVERS_TOOLS set links uv into
# $DRIVERS_TOOLS/.bin, which would mask the directory the shape under test
# actually installed into. Unset it so the assertion below sees the real one.
reset_env() {
  mkdir -p "$WORK/home" "$WORK/tmp"
  export HOME="$WORK/home"
  export TMPDIR="$WORK/tmp"
  export DRIVERS_TOOLS=""
  # Unset so ensure_uv cannot be steered to an interpreter the shape is not
  # testing (a sourced .env or the host may set it).
  unset DRIVERS_TOOLS_PYTHON
  # Drop any preinstalled uv on the host (e.g. under ~/.local/bin, or linked
  # into $DRIVERS_TOOLS/.bin by an earlier task) so ensure_uv has to install one
  # rather than short-circuiting on what is already there. handle-paths.sh
  # prepends the checkout's .bin, so strip those directories too.
  local cleaned
  cleaned="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vE '/\.bin$|/[^:]*\.local/bin$' | paste -sd: -)"
  export PATH="$cleaned"
}

test_inside_active_venv() {
  local outer="$WORK/outer"
  python3 -m venv --clear "$outer"
  echo "Testing ensure_uv inside an active venv ..."
  (
    reset_env
    export VIRTUAL_ENV="$outer"
    export PATH="$outer/bin:$PATH"
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    uv --version >/dev/null
    case "$(command -v uv)" in
    "$outer/bin/"* | "$outer/Scripts/"*) ;;
    *) echo "expected uv from the active venv, got $(command -v uv)" >&2; return 1 ;;
    esac
  )
  echo "Testing ensure_uv inside an active venv ... done."
}

test_no_venv_module() {
  local stub="$WORK/novenv"
  mkdir -p "$stub/venv"
  printf 'raise ImportError("venv disabled for test")\n' >"$stub/venv/__init__.py"
  echo "Testing ensure_uv without a venv module ..."
  (
    reset_env
    export PYTHONPATH="$stub"
    if python3 -c 'import venv' >/dev/null 2>&1; then
      echo "expected the venv module to be disabled; this test is no longer testing anything" >&2
      exit 1
    fi
    # shellcheck source=../ensure-uv.sh
    . "$ENSURE_UV"
    ensure_uv
    uv --version >/dev/null
    case "$(command -v uv)" in
    *drivers-tools-uv-venv*) echo "expected uv from the pip path, got $(command -v uv)" >&2; return 1 ;;
    esac
  )
  echo "Testing ensure_uv without a venv module ... done."
}

test_inside_active_venv
test_no_venv_module

make -C "$DRIVERS_TOOLS" test
