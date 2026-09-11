#!/usr/bin/env bash
#
# Regression tests for two ensure_uv install cases that no VM image reproduces:
# inside an active venv, and pip-without-venv. Runs in a private HOME/TMPDIR and
# skips on hosts that cannot reproduce a case.
set -eu -o pipefail

SCRIPT_DIR=$(dirname "${BASH_SOURCE[0]}")
. "$SCRIPT_DIR/../handle-paths.sh"

if [ "$(uname -s)" != "Darwin" ] && [ "$(uname -s)" != "Linux" ]; then
  echo "test-ensure-uv.sh: only runs on Linux and macOS; skipping."
  make -C "$DRIVERS_TOOLS" test
  exit 0
fi

if ! python3 -m venv --help >/dev/null 2>&1 || ! python3 -m pip --version >/dev/null 2>&1; then
  echo "test-ensure-uv.sh: python3-venv and python3-pip not available; skipping."
  make -C "$DRIVERS_TOOLS" test
  exit 0
fi

ENSURE_UV="$SCRIPT_DIR/../ensure-uv.sh"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/ensure-uv-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ensure_uv installs uv into $DRIVERS_TOOLS/.bin. Point DRIVERS_TOOLS at a temp
# dir so the checkout's .bin is untouched, clear the interpreter hints, and drop
# any preinstalled uv so ensure_uv has to install one.
reset_env() {
  mkdir -p "$WORK/home" "$WORK/tmp"
  export HOME="$WORK/home"
  export TMPDIR="$WORK/tmp"
  # A fresh bin per case so one case's uv does not satisfy the next.
  local tools_dir
  tools_dir="$(mktemp -d "$WORK/tools.XXXXXX")"
  export DRIVERS_TOOLS="$tools_dir"
  unset DRIVERS_TOOLS_PYTHON VIRTUAL_ENV
  local cleaned
  cleaned="$(printf '%s' "$PATH" | tr ':' '\n' | grep -vE '/\.bin$|/[^:]*\.local/bin$' | paste -sd: -)"
  export PATH="$cleaned"
}

# Fail unless uv is installed at $DRIVERS_TOOLS/.bin/uv and runs.
assert_in_bin() {
  local actual
  actual="$(command -v uv)"
  [ "$actual" = "$DRIVERS_TOOLS/.bin/uv" ] || {
    echo "expected uv at $DRIVERS_TOOLS/.bin/uv, got ${actual:-<none>}" >&2
    return 1
  }
  uv --version >/dev/null
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
    assert_in_bin
    # The venv branch installs into the active venv; a copy of it is what got
    # installed, so the venv now carries uv of its own.
    [ -x "$outer/bin/uv" ] || [ -x "$outer/Scripts/uv.exe" ] || {
      echo "expected uv installed into the active venv" >&2
      return 1
    }
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
    assert_in_bin
    # pip is the only way through, so the venv fallback must not have run.
    if [ -e "$WORK/tmp/drivers-tools-uv-venv" ]; then
      echo "expected uv from the pip path, not the fallback venv" >&2
      return 1
    fi
  )
  echo "Testing ensure_uv without a venv module ... done."
}

test_inside_active_venv
test_no_venv_module

make -C "$DRIVERS_TOOLS" test
