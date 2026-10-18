#!/usr/bin/env bash
#
# audit-perms.sh — security scan for world-writable, SUID and SGID files
#   commands showcased: find -perm, awk
#
# Usage: ./audit-perms.sh [options] [PATH]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
audit-perms.sh — security scan for world-writable, SUID and SGID files

Usage: $0 [options] [PATH]

Arguments:
  PATH           directory to scan (default: /)

Options:
  -n LIMIT       cap results shown per category (default: 50)
  -h, --help     show this help and exit

Notes:
  Read-only. No root required, but running as root surfaces more files
  (it can traverse directories an unprivileged user cannot).
EOF
}

# Run one scan: $1 = human label, rest = find predicate args.
scan() {
  local label="$1"; shift
  banner "$label"

  local count=0
  # find errors (permission denied) are silenced; results are capped by LIMIT.
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    count=$((count + 1))
    if [[ "$count" -le "$LIMIT" ]]; then
      printf '  %s\n' "$line"
    fi
  done < <(find "$SCAN_PATH" -xdev "$@" 2>/dev/null)

  if [[ "$count" -eq 0 ]]; then
    c_ok "none found"
  elif [[ "$count" -gt "$LIMIT" ]]; then
    c_warn "showing $LIMIT of $count results (raise with -n)"
  else
    c_info "$count result(s)"
  fi
}

main() {
  LIMIT=50
  SCAN_PATH="/"

  local opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) LIMIT="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG" ;;
    esac
  done
  shift $((OPTIND - 1))

  # Long help after getopts (e.g. `audit-perms.sh --help`).
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
  esac

  [[ -n "${1:-}" ]] && SCAN_PATH="$1"

  [[ "$LIMIT" =~ ^[0-9]+$ ]] || die "-n LIMIT must be a non-negative integer"
  [[ -d "$SCAN_PATH" ]] || die "not a directory: $SCAN_PATH"

  need_cmd find

  c_info "scanning '$SCAN_PATH' (one filesystem, -xdev), up to $LIMIT per category"

  scan "World-writable files" -type f -perm -0002
  scan "SUID files (-perm -4000)" -type f -perm -4000
  scan "SGID files (-perm -2000)" -type f -perm -2000

  hr
  c_ok "audit complete"
}

main "$@"
