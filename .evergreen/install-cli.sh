#!/usr/bin/env bash
# Install the drivers orchestration scripts.

set -eu

if [ -z "$BASH" ]; then
  echo "install-cli.sh must be run in a Bash shell!" 1>&2
  return 1
fi

TARGET_DIR="${1:?"must give a target directory!"}"

SCRIPT_DIR=$(dirname ${BASH_SOURCE[0]})
. $SCRIPT_DIR/handle-paths.sh

pushd $SCRIPT_DIR >/dev/null

# Ensure a working uv is on PATH; ensure_uv also configures its cache and tool
# dirs. The CLI then pins the desired uv version below.
. ./ensure-uv.sh
ensure_uv || exit 1

# Ensure there is a venv available in the script dir for backward compatibility.
if [ ! -d venv ]; then
  uv venv -p "${DRIVERS_TOOLS_PYTHON:-python}" venv &>/dev/null || uv venv venv
fi
[[ -d venv ]]

popd >/dev/null # $SCRIPT_DIR
pushd "$TARGET_DIR" >/dev/null

# uv requires UV_TOOL_BIN_DIR is `C:\a\b\c` instead of `/cygdrive/c/a/b/c` on Windows.
if [[ "${OSTYPE:?}" == cygwin ]]; then
  UV_TOOL_BIN_DIR="$(cygpath -aw .)"
else
  UV_TOOL_BIN_DIR="$(pwd)"
fi
export UV_TOOL_BIN_DIR

[[ "${PATH:-}" =~ (^|:)"${UV_TOOL_BIN_DIR:?}"(:|$) ]] || PATH="${UV_TOOL_BIN_DIR:?}:${PATH:-}"

# Pin the uv version the CLI tooling uses, so it is reproducible. The source of
# truth is the repo's requirements-uv.txt; versions uv already satisfies are
# left alone.
UV_SPEC="$(sed -n 's/^uv//p' "$SCRIPT_DIR/../requirements-uv.txt" 2>/dev/null | head -n1)" || true
uv tool install -q --force "uv${UV_SPEC:-}"
command -V uv
uv --version

# Workaround for https://github.com/astral-sh/uv/issues/5815.
uv export --quiet --frozen --format requirements.txt -o uv-requirements.txt

# Support overriding lockfile dependencies.
if [[ ! -f "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:-}" ]]; then
  printf "" >|"${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:="uv-override-dependencies.txt"}"
fi

declare uv_install_args
uv_install_args=(
  --quiet
  --force
  --editable
  --with-requirements uv-requirements.txt
  --overrides "${DRIVERS_TOOLS_INSTALL_CLI_OVERRIDES:?}"
)
uv tool install "${uv_install_args[@]:?}" .

# Support running tool executables on Windows without including the ".exe" suffix.
(
  for name_exe in *.exe; do
    # Skip files which do not exist or are not executable.
    [[ -x "${name_exe:?}" ]] || continue
    # Strip ".exe" at end of filename.
    name="${name_exe%".exe"}"
    # Only create a symlink if the symlink doesn't already exist.
    [[ -x "${name:?}" ]] || ln -sf "${name_exe:?}" "${name:?}"
  done
)

popd >/dev/null # "$TARGET_DIR"
