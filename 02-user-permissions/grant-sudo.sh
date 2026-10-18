#!/usr/bin/env bash
#
# grant-sudo.sh — add a user to the sudo/wheel admin group
#   commands showcased: usermod -aG, getent group, id
#
# Usage: ./grant-sudo.sh -u USER [--dry-run] [--yes]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
grant-sudo.sh — add a user to the sudo/wheel admin group

Usage: $0 -u USER [options]

Options:
  -u, --user USER  user to grant admin rights to (required)
  --dry-run        print the command instead of running it (DRY_RUN=1)
  --yes            skip the confirmation prompt (ASSUME_YES=1)
  -h, --help       show this help and exit

Notes:
  Needs root; a dry run previews without it. Auto-detects the 'sudo'
  group, falling back to 'wheel'.

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local user=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user) need_arg "$@"; user="$2"; shift 2 ;;
      --dry-run) export DRY_RUN=1; shift ;;
      --yes)     export ASSUME_YES=1; shift ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ -n "$user" ]] || usage_error "missing required option: -u/--user USER"

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

  confirm_or_abort "Add user '$user' to group '$admin_group'?"

  run usermod -aG "$admin_group" "$user"
  [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "added '$user' to '$admin_group'"

  hr
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    id "$user"
    c_info "the new group applies to fresh login sessions"
  else
    c_info "(dry-run) would print: id $user"
  fi
}

main "$@"
