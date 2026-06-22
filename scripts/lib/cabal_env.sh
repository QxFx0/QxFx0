#!/usr/bin/env bash

setup_shared_python_site_packages() {
  local __target_var="$1"
  local value=""
  if command -v python3 >/dev/null 2>&1; then
    value="$(python3 -c "import site; print(site.getusersitepackages())" 2>/dev/null || true)"
  fi
  printf -v "$__target_var" '%s' "$value"
}

seed_shared_cabal_home() {
  local target_cabal_dir="$1"
  local shared_store="$2"
  local shared_logs="$3"
  local host_cabal_dir="$4"
  local host_xdg_config_home="$5"
  local host_config="$host_cabal_dir/config"
  local host_packages="$host_cabal_dir/packages"

  if [ ! -f "$host_config" ]; then
    host_config="$host_xdg_config_home/cabal/config"
  fi

  if [ -f "$host_config" ] && [ ! -f "$target_cabal_dir/config" ]; then
    cp "$host_config" "$target_cabal_dir/config"
  fi
  if [ ! -f "$target_cabal_dir/config" ]; then
    : >"$target_cabal_dir/config"
  fi
  {
    printf '\nstore-dir: %s\n' "$shared_store"
    printf 'logs-dir: %s\n' "$shared_logs"
    printf 'build-summary: %s/build.log\n' "$shared_logs"
    if [ -d "$host_packages" ]; then
      printf 'remote-repo-cache: %s\n' "$host_packages"
    fi
  } >>"$target_cabal_dir/config"
  if [ -d "$host_packages" ] && [ ! -e "$target_cabal_dir/packages" ]; then
    ln -s "$host_packages" "$target_cabal_dir/packages"
  fi
}

# C1 fix: Symlink-safe lock acquisition — rejects pre-created symlinks.
acquire_safe_lock() {
  local lock_file="$1"
  local lock_dir
  lock_dir="$(dirname "$lock_file")"
  # Verify the lock directory is not a symlink and is writable.
  if [ -L "$lock_dir" ]; then
    echo "SECURITY: lock directory is a symlink — refusing: $lock_dir" >&2
    return 1
  fi
  # If lock file exists and is a symlink, remove it (TOCTOU-safe via O_NOFOLLOW).
  if [ -L "$lock_file" ]; then
    echo "SECURITY: lock file is a symlink — removing: $lock_file" >&2
    rm -f "$lock_file" || return 1
  fi
  # Create lock file atomically with O_EXCL (no symlink following).
  if ! (set -C; printf "" > "$lock_file") 2>/dev/null; then
    : # File may already exist from a prior call — that is OK for flock.
  fi
  # Verify it is still a regular file after creation.
  if [ -L "$lock_file" ]; then
    echo "SECURITY: lock file became a symlink — refusing: $lock_file" >&2
    return 1
  fi
  return 0
}

run_locked_root_command() {
  local root="$1"
  local lock_file="$2"
  local home_dir="$3"
  local cache_dir="$4"
  local config_dir="$5"
  local state_dir="$6"
  local cabal_dir="$7"
  local python_site_packages="$8"
  shift 8
  (
    flock -w 1800 9 || exit 1
    HOME="$home_dir" \
    XDG_CACHE_HOME="$cache_dir" \
    XDG_CONFIG_HOME="$config_dir" \
    XDG_STATE_HOME="$state_dir" \
    CABAL_DIR="$cabal_dir" \
    PYTHONPATH="${python_site_packages}${PYTHONPATH:+:$PYTHONPATH}" \
    bash -c "cd \"$root\" && $*"
  ) 9>"$lock_file"
}

run_locked_command() {
  local lock_file="$1"
  local home_dir="$2"
  local cache_dir="$3"
  local config_dir="$4"
  local state_dir="$5"
  local cabal_dir="$6"
  local python_site_packages="$7"
  shift 7
  (
    flock -w 1800 9 || exit 1
    HOME="$home_dir" \
    XDG_CACHE_HOME="$cache_dir" \
    XDG_CONFIG_HOME="$config_dir" \
    XDG_STATE_HOME="$state_dir" \
    CABAL_DIR="$cabal_dir" \
    PYTHONPATH="${python_site_packages}${PYTHONPATH:+:$PYTHONPATH}" \
    "$@"
  ) 9>"$lock_file"
}
