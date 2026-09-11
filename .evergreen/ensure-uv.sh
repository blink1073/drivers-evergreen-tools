#!/usr/bin/env bash
#
# ensure-uv.sh
#
# Usage:
#   . /path/to/ensure-uv.sh
#   ensure_uv || exit 1
#
# This file defines the following utility function:
#   - ensure_uv
# This function may be invoked from any working directory.

if [ -z "$BASH" ]; then
  echo "ensure-uv.sh must be run in a Bash shell!" 1>&2
  return 1
fi

# _ensure_uv_add_path (internal)
#
# Prepend $1 to PATH unless it is already there, which keeps repeated ensure_uv
# calls from growing PATH without end. Not meant to be called directly.
_ensure_uv_add_path() {
  declare dir="${1:?}"
  case ":${PATH:-}:" in
  *":$dir:"*) ;;
  *) export PATH="$dir:${PATH:-}" ;;
  esac
}

# _ensure_uv_defer_to_pyenv_global (internal)
#
# pyenv shims enforce whichever .python-version file sits above the working
# directory; on the RHEL 8 zseries and power8 hosts that file names a version
# pyenv lacks, so even `uv --version` fails. When a .python-version is in play,
# defer to pyenv's global version. A no-op otherwise, and when pyenv is absent.
# Not meant to be called directly.
_ensure_uv_defer_to_pyenv_global() {
  command -v pyenv >/dev/null 2>&1 || return 0

  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -e "$dir/.python-version" ]; then
      local pyenv_global
      pyenv_global="$(pyenv global 2>/dev/null | head -n1)" || true
      [ -n "$pyenv_global" ] && export PYENV_VERSION="$pyenv_global"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
}

# _ensure_uv_toolchain_pythons (internal)
#
# Print the MongoDB toolchain python interpreters, newest version first. GNU
# sort -V is unavailable on the BSD sort that shipped before macOS 26, so fall
# back to plain reverse sort; the sparse vN.n names order correctly that way.
# Not meant to be called directly.
_ensure_uv_toolchain_pythons() {
  local paths
  paths="$(compgen -G '/opt/mongodbtoolchain/v*/bin/python3' 2>/dev/null)" || return 0
  [ -n "$paths" ] || return 0
  printf '%s\n' "$paths" | sort -Vr 2>/dev/null || printf '%s\n' "$paths" | sort -r
}

# _ensure_uv_candidate_paths (internal)
#
# Print paths to a uv in the places ensure_uv installs into, most preferred
# first, without touching PATH: an active venv, the tools venv, and the pip
# --user directory. Not meant to be called directly.
_ensure_uv_candidate_paths() {
  declare venv_dir="${1:-}" py="${2:-}"

  if [ -n "${VIRTUAL_ENV:-}" ]; then
    printf '%s\n' "$VIRTUAL_ENV/bin/uv" "$VIRTUAL_ENV/Scripts/uv.exe"
  fi
  [ -n "$venv_dir" ] && printf '%s\n' "$venv_dir/bin/uv" "$venv_dir/Scripts/uv.exe"

  [ -n "$py" ] || return 0
  local user_base
  user_base="$("$py" -m site --user-base 2>/dev/null)" || return 0
  printf '%s\n' "$user_base/bin/uv" "$user_base/Scripts/uv.exe"
}

# _ensure_uv_locate (internal)
#
# Print the first candidate uv that actually runs, or nothing. Not meant to be
# called directly.
_ensure_uv_locate() {
  local candidate
  for candidate in $(_ensure_uv_candidate_paths "${1:-}" "${2:-}"); do
    [ -x "$candidate" ] || continue
    "$candidate" --version >/dev/null 2>&1 || continue
    printf '%s\n' "$candidate"
    return 0
  done
}

# _ensure_uv_in_bin (internal)
#
# Return 0 when a working uv is already at $DRIVERS_TOOLS/.bin, making sure that
# directory is on PATH. Not meant to be called directly.
_ensure_uv_in_bin() {
  [ -n "${DRIVERS_TOOLS:-}" ] || return 1
  declare dest="$DRIVERS_TOOLS/.bin"
  [ -x "$dest/uv" ] || return 1
  "$dest/uv" --version >/dev/null 2>&1 || return 1
  _ensure_uv_add_path "$dest"
  return 0
}

# _ensure_uv_copy_into_bin (internal)
#
# Copy the known-good uv ensure_uv just installed into $DRIVERS_TOOLS/.bin, so
# the repo has one uv on PATH. uv is a standalone binary, so a copy is
# self-contained and cannot dangle. Returns 0 when uv is usable there, non-zero
# otherwise. Not meant to be called directly.
_ensure_uv_copy_into_bin() {
  [ -n "${DRIVERS_TOOLS:-}" ] || return 1

  declare dest="$DRIVERS_TOOLS/.bin"
  mkdir -p "$dest" 2>/dev/null || return 1

  declare src
  src="$(_ensure_uv_locate "${1:-}" "${2:-}")"
  [ -n "$src" ] || return 1

  [ "$src" = "$dest/uv" ] && { _ensure_uv_add_path "$dest"; return 0; }

  cp -f "$src" "$dest/uv" 2>/dev/null || return 1
  _ensure_uv_add_path "$dest"
}

# _ensure_uv_scope_paths (internal)
#
# Move uv's cache and tool directories out of the home directory, which Evergreen
# hosts contend over when they share one. Inside the repo's Docker containers
# that is a fresh temp dir; under CI it is $TMPDIR, recycled with the task;
# elsewhere only UV_TOOL_DIR moves, since `uv tool install --force` would
# otherwise overwrite a developer's own tools.
#
# Best-effort, and a no-op when there is nowhere to point at. Not meant to be
# called directly.
_ensure_uv_scope_paths() {
  if [ "${DOCKER_RUNNING:-}" = "true" ]; then
    declare _root
    _root="$(mktemp -d)"
    export UV_CACHE_DIR="$_root/uv-cache"
    export UV_TOOL_DIR="$_root/uv-tool"
    export UV_PYTHON_INSTALL_DIR="$_root/uv-python"
    return 0
  fi

  if [ -n "${CI:-}" ]; then
    declare _tmp="${TMPDIR:-${TEMP:-${TMP:-}}}"
    if [ -n "$_tmp" ]; then
      # Strip any trailing slash, and match handle-paths.sh in giving uv a
      # native Windows path -- it rejects /cygdrive/c/... style paths.
      _tmp="${_tmp%/}"
      if [ "${OSTYPE:-}" = cygwin ]; then
        _tmp="$(cygpath -m "$_tmp")"
      fi
      export UV_CACHE_DIR="$_tmp/uv-cache"
      export UV_TOOL_DIR="$_tmp/uv-tool"
      export UV_PYTHON_INSTALL_DIR="$_tmp/uv-python"
      return 0
    fi
  fi

  [ -n "${DRIVERS_TOOLS:-}" ] || return 0
  export UV_TOOL_DIR="${DRIVERS_TOOLS}/.local/uv-tool"
}

# _ensure_uv_install (internal)
#
# Install uv with interpreter $1, using $2 for the virtual-environment fallback
# and appending all output to $3. pip is tried first; a venv is the fallback when
# there is no pip, or when pip leaves uv missing. Not meant to be called directly.
_ensure_uv_install() {
  declare py="${1:?}" venv_dir="${2:?}" log="${3:?}"
  declare uv_pkg="uv$UV_VERSION"

  if "$py" -m pip --version >>"$log" 2>&1; then
    if "$py" -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'; then
      # pip refuses --user inside a venv, and the venv is the right target anyway.
      # This is how the Node OIDC tests call ensure_uv.
      echo "uv not found; installing it with '$py -m pip install $uv_pkg' into the venv..." >&2
      "$py" -m pip install -q "$uv_pkg" >>"$log" 2>&1 || true
    else
      # PIP_BREAK_SYSTEM_PACKAGES bypasses PEP 668's externally-managed guard,
      # which Debian and Ubuntu enable. Safe here: --user leaves system
      # site-packages alone.
      echo "uv not found; installing it with '$py -m pip install --user $uv_pkg'..." >&2
      PIP_BREAK_SYSTEM_PACKAGES=1 "$py" -m pip install --user -q "$uv_pkg" >>"$log" 2>&1 || true
    fi
    [ -n "$(_ensure_uv_locate "$venv_dir" "$py")" ] && return 0
  fi

  # No pip at all, or the pip install ended without a usable uv (Debian refuses
  # ensurepip outside a venv). A venv is the fallback either way.
  echo "uv still not found; building a virtual environment at $venv_dir..." >&2
  if "$py" -m venv --clear "$venv_dir" >>"$log" 2>&1; then
    # Windows venvs put the interpreter under Scripts, everything else in bin.
    declare venv_py="$venv_dir/bin/python"
    [ -x "$venv_py" ] || venv_py="$venv_dir/Scripts/python.exe"
    "$venv_py" -m pip install -q "$uv_pkg" >>"$log" 2>&1 || true
  fi
}

# ensure_uv
#
# Find or install a known-good uv in $DRIVERS_TOOLS/.bin. Returns non-zero and
# prints a debug log on failure. It is safe to call repeatedly.
ensure_uv() {
  _ensure_uv_defer_to_pyenv_global

  # UV_VERSION is the known-good uv version this repo installs, overridable so a
  # consumer can pin its own. The default comes from the repo's
  # requirements-uv.txt so the version is obvious and dependabot can bump it,
  # falling back to a built-in version if the file is absent. UV_UNMANAGED_INSTALL
  # keeps uv from trying to self-manage an install we placed ourselves.
  if [ -z "${UV_VERSION:-}" ]; then
    local ensure_uv_dir uv_spec
    ensure_uv_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" 2>/dev/null || ensure_uv_dir=""
    uv_spec="$(sed -n 's/^uv//p' "$ensure_uv_dir/../requirements-uv.txt" 2>/dev/null | head -n1)" || true
    UV_VERSION="${uv_spec:-~=0.12.0}"
  fi
  export UV_VERSION
  export UV_UNMANAGED_INSTALL="${UV_UNMANAGED_INSTALL:-1}"

  # Stable rather than mktemp'd, so a later call in a fresh shell reuses the venv.
  declare venv_dir="${TMPDIR:-/tmp}"
  venv_dir="${venv_dir%/}/drivers-tools-uv-venv"

  # The known-good uv is already in $DRIVERS_TOOLS/.bin; nothing to do.
  if _ensure_uv_in_bin; then
    _ensure_uv_scope_paths
    return 0
  fi

  # Otherwise pick an interpreter to install the known-good uv with:
  # $DRIVERS_TOOLS_PYTHON, an active venv, the toolchain, then system python3.
  # Skip one that is too old or cannot install uv (no pip and no venv), so it
  # does not preempt a python3 that would work. Use absolute paths so a venv
  # later on PATH cannot re-point the name.
  declare py="" candidate resolved
  for candidate in \
    "${DRIVERS_TOOLS_PYTHON:-}" \
    "${VIRTUAL_ENV:+$VIRTUAL_ENV/bin/python}" \
    "${VIRTUAL_ENV:+$VIRTUAL_ENV/Scripts/python.exe}" \
    $(_ensure_uv_toolchain_pythons) \
    python3 \
    python; do
    [ -n "$candidate" ] || continue
    resolved="$(command -v "$candidate" 2>/dev/null)" || continue
    [ -n "$resolved" ] || continue
    "$resolved" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' >/dev/null 2>&1 || continue
    "$resolved" -c 'import venv' >/dev/null 2>&1 || "$resolved" -m pip --version >/dev/null 2>&1 || continue
    py="$resolved"
    break
  done

  [ -n "$py" ] || {
    echo "ERROR: no Python 3.8+ interpreter with pip or venv was found." >&2
    return 1
  }

  # We collect logs so we can display just the tail later for debugging.
  # The log is discarded if $TMPDIR is read-only.
  declare log="${venv_dir}-install.log"
  : >"$log" 2>/dev/null || log=/dev/null

  _ensure_uv_install "$py" "$venv_dir" "$log"

  if _ensure_uv_copy_into_bin "$venv_dir" "$py"; then
    _ensure_uv_scope_paths
    return 0
  fi

  if [ "$log" != /dev/null ] && [ -s "$log" ]; then
    echo "Last output from the failed install attempts (full log: $log):" >&2
    tail -n 20 "$log" | sed 's/^/  /' >&2
    echo >&2
  fi

  # Fall back to a helpful message for the user.
  cat <<'EOF' >&2
ERROR: could not find or install `uv`.

Install it manually, then re-run:
  https://docs.astral.sh/uv/getting-started/installation/

If you believe uv/pip should already be available in this environment,
please file a ticket in the DEVPROD Jira project:
  https://jira.mongodb.org/projects/DEVPROD
EOF
  return 1
}
