#!/usr/bin/env bash
#
# dirsnap.sh — per-subdirectory size snapshot, sorted largest-first, top-N
#   commands showcased: du, sort, head, find, pwd
#
# Usage: ./dirsnap.sh [-n N] [-a] [PATH]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
dirsnap.sh — per-subdirectory size snapshot, sorted largest-first, top-N

Usage: $0 [options] [PATH]

Arguments:
  PATH           directory to inspect (default: current directory)

Options:
  -n, --top N    show only the top N subdirectories (default: 10)
  -a, --all      include hidden subdirectories (names starting with '.')
  -h, --help     show this help and exit

Exit status: 0 on success, 1 if PATH is not a directory, 2 on a usage error.

Read-only: this script never modifies anything.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local top=10 include_hidden=0
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--top) need_arg "$@"; top="$2"; shift 2 ;;
      -a|--all) include_hidden=1; shift ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one PATH (got ${#args[@]} arguments)"
  [[ "$top" =~ ^[1-9][0-9]*$ ]] || usage_error "--top must be a positive integer (got '$top')"
  local target="${args[0]:-.}"
  [[ -d "$target" ]] || die "not a directory: $target"

  need_cmd du
  need_cmd sort
  need_cmd head
  need_cmd find

  local abs
  abs="$(cd "$target" && pwd)"

  banner "Directory snapshot"
  c_info "Path:        $abs"
  c_info "Top entries: $top"
  if [[ "$include_hidden" -eq 1 ]]; then
    c_info "Hidden dirs: included"
  else
    c_info "Hidden dirs: excluded"
  fi
  hr

  # Collect immediate subdirectories (depth 1). Use -print0 / NUL-safe read so
  # directory names with spaces or newlines are handled correctly.
  local -a subdirs=()
  local d
  while IFS= read -r -d '' d; do
    local base
    base="$(basename "$d")"
    if [[ "$include_hidden" -eq 0 && "$base" == .* ]]; then
      continue
    fi
    subdirs+=("$d")
  done < <(find "$target" -mindepth 1 -maxdepth 1 -type d -print0)

  if [[ "${#subdirs[@]}" -eq 0 ]]; then
    c_warn "No subdirectories found under $abs"
  else
    # du -sh on every subdir, sort by human-readable size descending, take top N.
    # du exits 1 when it meets an unreadable entry but still prints the sizes it
    # could read; with pipefail that status would abort the script, so it is
    # tolerated. awk takes the top N without closing the pipe early like head.
    { du -sh "${subdirs[@]}" 2>/dev/null || true; } | sort -rh | awk -v n="$top" 'NR <= n'
  fi

  hr
  local total
  total="$(du -sh "$target" 2>/dev/null | cut -f1)" || true
  c_ok "Total size of $abs: ${total:-unknown}"
}

main "$@"
