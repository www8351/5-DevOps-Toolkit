#!/usr/bin/env bash
#
# bigfiles.sh — list the N largest files under a path, human-readable sizes
#   commands showcased: find, du, sort, head
#
# Usage: ./bigfiles.sh [-n N] [-s MINSIZE] [PATH]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
bigfiles.sh — list the N largest files under a path, human-readable sizes

Usage: $0 [options] [PATH]

Arguments:
  PATH           directory to search (default: current directory)

Options:
  -n N           show only the top N files (default: 15)
  -s MINSIZE     only consider files matching find -size MINSIZE (e.g. +10M)
  -h, --help     show this help and exit

Read-only: this script never modifies anything.
EOF
}

# Turn a byte count into a human-readable size. Prefers numfmt when present,
# otherwise falls back to a small awk formatter so the script still works.
humanize() {
  local bytes="$1"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec --suffix=B --format="%.1f" "$bytes"
  else
    awk -v b="$bytes" '
      function fmt(x,   u, i) {
        split("B KB MB GB TB PB", u, " ")
        i = 1
        while (x >= 1024 && i < 6) { x /= 1024; i++ }
        return sprintf("%.1f%s", x, u[i])
      }
      BEGIN { print fmt(b) }'
  fi
}

main() {
  local top=15
  local minsize=""

  if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local opt
  while getopts ":n:s:h" opt; do
    case "$opt" in
      n) top="$OPTARG" ;;
      s) minsize="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG (see -h)" ;;
    esac
  done
  shift "$((OPTIND - 1))"

  local target="${1:-.}"

  [[ "$top" =~ ^[0-9]+$ && "$top" -gt 0 ]] || die "-n must be a positive integer (got '$top')"
  [[ -d "$target" ]] || die "not a directory: $target"

  need_cmd find
  need_cmd sort
  need_cmd head
  need_cmd awk

  banner "Largest files"
  c_info "Path: $target"
  c_info "Top:  $top"
  if [[ -n "$minsize" ]]; then
    c_info "Size: find -size $minsize"
  fi
  hr

  # Build the find argument list safely as an array.
  local -a find_args=("$target" -type f)
  if [[ -n "$minsize" ]]; then
    find_args+=(-size "$minsize")
  fi

  # Capture "<bytes>\t<path>" lines from find. Prefer GNU -printf for speed;
  # if it is unsupported, fall back to 'du -b' via -exec.
  local raw=""
  if raw="$(find "${find_args[@]}" -printf '%s\t%p\n' 2>/dev/null)"; then
    : # GNU find succeeded
  else
    need_cmd du
    c_warn "find -printf unsupported here; falling back to du -b"
    raw="$(find "${find_args[@]}" -exec du -b {} + 2>/dev/null)"
  fi

  if [[ -z "$raw" ]]; then
    c_warn "No matching files found under $target"
    return 0
  fi

  printf '%-12s | %s\n' "SIZE" "PATH"
  hr

  # Sort by the leading byte count (numeric, descending), keep top N, then
  # humanize the size column. Read NUL-free tab-delimited lines.
  local bytes path human
  while IFS=$'\t' read -r bytes path; do
    [[ -n "$bytes" ]] || continue
    human="$(humanize "$bytes")"
    printf '%-12s | %s\n' "$human" "$path"
  done < <(printf '%s\n' "$raw" | sort -rn | head -n "$top")

  hr
  c_ok "Listed up to $top largest file(s) under $target"
}

main "$@"
