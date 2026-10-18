#!/usr/bin/env bash
#
# whohas.sh — read-only identity report for a user (uid, gid, home, shell, groups)
#   commands showcased: awk -F: /etc/passwd, /etc/group, id, getent
#
# Usage: ./whohas.sh [USER]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
whohas.sh — read-only identity report for a user

Usage: $0 [USER]

Arguments:
  USER           user to report on (default: current user)

Options:
  -h, --help     show this help and exit

Notes:
  Read-only. No root required.

Exit status: 0 on success, 1 if USER does not exist, 2 on a usage error.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one USER (got ${#args[@]} arguments)"
  set -- "${args[@]}"

  need_cmd id
  need_cmd awk

  local user
  if [[ -n "${1:-}" ]]; then
    user="$1"
  else
    user="$(id -un)"
  fi

  # Pull the passwd entry once; getent falls back to /etc/passwd when no NSS.
  local pwline
  if command -v getent >/dev/null 2>&1; then
    pwline="$(getent passwd "$user" || true)"
  else
    pwline="$(awk -F: -v u="$user" '$1 == u {print; exit}' /etc/passwd || true)"
  fi

  [[ -n "$pwline" ]] || die "user '$user' not found"

  local uid gid home shell
  uid="$(awk -F: '{print $3}' <<<"$pwline")"
  gid="$(awk -F: '{print $4}' <<<"$pwline")"
  home="$(awk -F: '{print $6}' <<<"$pwline")"
  shell="$(awk -F: '{print $7}' <<<"$pwline")"

  # Primary group name from the gid.
  local pgroup
  if command -v getent >/dev/null 2>&1; then
    pgroup="$(getent group "$gid" | awk -F: '{print $1}')"
  else
    pgroup="$(awk -F: -v g="$gid" '$3 == g {print $1; exit}' /etc/group)"
  fi
  [[ -n "$pgroup" ]] || pgroup="(gid $gid)"

  banner "Identity report: $user"
  printf '  %-14s %s\n' "Username:" "$user"
  printf '  %-14s %s\n' "UID:" "$uid"
  printf '  %-14s %s (%s)\n' "Primary GID:" "$gid" "$pgroup"
  printf '  %-14s %s\n' "Home:" "$home"
  printf '  %-14s %s\n' "Shell:" "$shell"

  hr
  c_info "Group memberships"

  # All groups (primary + supplementary) via id -nG, space separated.
  local -a groups=()
  read -ra groups <<<"$(id -nG "$user" 2>/dev/null || true)"
  if [[ "${#groups[@]}" -gt 0 ]]; then
    local g
    for g in "${groups[@]}"; do
      if [[ "$g" == "$pgroup" ]]; then
        printf '  %s (primary)\n' "$g"
      else
        printf '  %s\n' "$g"
      fi
    done
  else
    c_warn "could not resolve group list for '$user'"
  fi
}

main "$@"
