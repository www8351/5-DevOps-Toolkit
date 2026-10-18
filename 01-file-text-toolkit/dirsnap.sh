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
  -n N           show only the top N subdirectories (default: 10)
  -a             include hidden subdirectories (names starting with '.')
  -h, --help     show this help and exit

Read-only: this script never modifies anything.
EOF
}

main() {
  local top=10
  local include_hidden=0

  # Support long help flag before getopts.
  if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local opt
  while getopts ":n:ah" opt; do
    case "$opt" in
      n) top="$OPTARG" ;;
      a) include_hidden=1 ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG (see -h)" ;;
    esac
  done
  shift "$((OPTIND - 1))"

  local target="${1:-.}"

  [[ "$top" =~ ^[0-9]+$ && "$top" -gt 0 ]] || die "-n must be a positive integer (got '$top')"
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
    du -sh "${subdirs[@]}" 2>/dev/null | sort -rh | head -n "$top"
  fi

  hr
  local total
  total="$(du -sh "$target" 2>/dev/null | cut -f1)"
  c_ok "Total size of $abs: ${total:-unknown}"
}

main "$@"
