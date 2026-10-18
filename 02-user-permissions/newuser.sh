#!/usr/bin/env bash
#
# newuser.sh — create a user with home, login shell and own group, then set a password
#   commands showcased: useradd, passwd, id, getent
#
# Usage: ./newuser.sh -u USER [options]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
newuser.sh — create a user with home, login shell and own group, then set a password

Usage: $0 -u USER [options]

Options:
  -u, --user USER     username to create (required)
  --shell SHELL       login shell (default: /bin/bash)
  --home DIR          home directory (default: /home/USER)
  --no-user-group     do NOT create a per-user group (passes -N instead of -U)
  --dry-run           print the commands instead of running them (DRY_RUN=1)
  --yes               skip the confirmation prompt (ASSUME_YES=1)
  -h, --help          show this help and exit

Deprecated (still work, removed in 2.0.0): -s SHELL (use --shell),
-d HOME (use --home), -N (use --no-user-group).

Notes:
  Needs root; a dry run previews without it.

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local user="" shell="/bin/bash" home="" group_flag="-U"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--user)       need_arg "$@"; user="$2"; shift 2 ;;
      --shell)         need_arg "$@"; shell="$2"; shift 2 ;;
      -s)              deprecated -s --shell; need_arg "$@"; shell="$2"; shift 2 ;;
      --home)          need_arg "$@"; home="$2"; shift 2 ;;
      -d)              deprecated -d --home; need_arg "$@"; home="$2"; shift 2 ;;
      --no-user-group) group_flag="-N"; shift ;;
      -N)              deprecated -N --no-user-group; group_flag="-N"; shift ;;
      --dry-run)       export DRY_RUN=1; shift ;;
      --yes)           export ASSUME_YES=1; shift ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ -n "$user" ]] || usage_error "missing required option: -u/--user USER"
  [[ -z "$home" ]] && home="/home/$user"

  require_root
  need_cmd useradd
  need_cmd getent
  need_cmd id

  # Guard: refuse if the user already exists.
  if getent passwd "$user" >/dev/null; then
    die "user '$user' already exists"
  fi

  banner "Create user: $user"
  c_info "shell : $shell"
  c_info "home  : $home"
  c_info "group : $([[ "$group_flag" == "-U" ]] && echo "own per-user group" || echo "no per-user group")"

  confirm_or_abort "Create user '$user' now?"

  run useradd -m -d "$home" -s "$shell" "$group_flag" "$user"
  [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "user '$user' created"

  # Set a password when running interactively; otherwise advise.
  if command -v passwd >/dev/null 2>&1; then
    if [[ -t 0 && "${DRY_RUN:-0}" != "1" ]]; then
      c_info "setting password for '$user'"
      run passwd "$user"
    else
      c_warn "not interactive (or dry-run); set a password later with: passwd $user"
    fi
  else
    c_warn "passwd not found; set a password with your password tooling"
  fi

  hr
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    id "$user"
  else
    c_info "(dry-run) would print: id $user"
  fi
}

main "$@"
