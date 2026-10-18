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
  -n, --limit N  cap results shown per category (default: 50, 0 = counts only)
  -h, --help     show this help and exit

Notes:
  Read-only. No root required, but running as root surfaces more files
  (it can traverse directories an unprivileged user cannot).

Exit status: 0 after a completed scan (findings are a report, not a failure),
1 if PATH is not a directory, 2 on a usage error.
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
  help_requested "$@" && { usage; exit 0; }

  LIMIT=50
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--limit) need_arg "$@"; LIMIT="$2"; shift 2 ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one PATH (got ${#args[@]} arguments)"
  [[ "$LIMIT" =~ ^[0-9]+$ ]] || usage_error "--limit must be a non-negative integer (got '$LIMIT')"
  SCAN_PATH="${args[0]:-/}"
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
