#!/usr/bin/env bash
#
# grant-sudo.sh — add a user to the sudo/wheel admin group
#   commands showcased: usermod -aG, getent group, id
#
# Usage: ./grant-sudo.sh -u USER
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
grant-sudo.sh — add a user to the sudo/wheel admin group

Usage: $0 -u USER

Options:
  -u USER        user to grant admin rights to (required)
  -h, --help     show this help and exit

Notes:
  Must run as root. Auto-detects 'sudo' group, falling back to 'wheel'.
  Honours DRY_RUN=1 and ASSUME_YES=1.
EOF
}

main() {
  local user=""

  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  local opt
  while getopts ":u:h" opt; do
    case "$opt" in
      u) user="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG" ;;
    esac
  done

  [[ -n "$user" ]] || { usage; die "missing required option: -u USER"; }

  require_root
  need_cmd usermod
  need_cmd getent
  need_cmd id

  # Guard: the user must exist.
  if ! getent passwd "$user" >/dev/null; then
    die "user '$user' does not exist"
  fi

  # Auto-detect the admin group: prefer 'sudo', else 'wheel'.
  local admin_group=""
  if getent group sudo >/dev/null; then
    admin_group="sudo"
  elif getent group wheel >/dev/null; then
    admin_group="wheel"
  else
    die "no admin group found (neither 'sudo' nor 'wheel' exists)"
  fi

  banner "Grant admin rights: $user -> $admin_group"

  confirm "Add user '$user' to group '$admin_group'?" || die "aborted by user"

  run usermod -aG "$admin_group" "$user"
  c_ok "added '$user' to '$admin_group'"

  hr
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    id "$user"
    c_info "the new group applies to fresh login sessions"
  else
    c_info "(dry-run) would print: id $user"
  fi
}

main "$@"
