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
  -u USER        username to create (required)
  -s SHELL       login shell (default: /bin/bash)
  -d HOME        home directory (default: /home/USER)
  -N             do NOT create a per-user group (passes -N instead of -U)
  -h, --help     show this help and exit

Notes:
  Must run as root. Honours DRY_RUN=1 and ASSUME_YES=1.
EOF
}

main() {
  local user="" shell="/bin/bash" home="" group_flag="-U"

  # Long help support before getopts.
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  local opt
  while getopts ":u:s:d:Nh" opt; do
    case "$opt" in
      u) user="$OPTARG" ;;
      s) shell="$OPTARG" ;;
      d) home="$OPTARG" ;;
      N) group_flag="-N" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG" ;;
    esac
  done

  [[ -n "$user" ]] || { usage; die "missing required option: -u USER"; }
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

  confirm "Create user '$user' now?" || die "aborted by user"

  run useradd -m -d "$home" -s "$shell" "$group_flag" "$user"
  c_ok "user '$user' created"

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
