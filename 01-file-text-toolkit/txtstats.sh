#!/usr/bin/env bash
#
# txtstats.sh — line/word/char stats plus head & tail preview of a text file
#   commands showcased: wc, head, tail, awk
#
# Usage: ./txtstats.sh [-n N] FILE
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
txtstats.sh — line/word/char stats plus head & tail preview of a text file

Usage: $0 [options] FILE

Arguments:
  FILE           text file to inspect (required)

Options:
  -n N           number of preview lines for head and tail (default: 5)
  -h, --help     show this help and exit

Read-only: this script never modifies anything.
EOF
}

main() {
  local preview=5

  if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local opt
  while getopts ":n:h" opt; do
    case "$opt" in
      n) preview="$OPTARG" ;;
      h) usage; exit 0 ;;
      :) die "option -$OPTARG requires an argument" ;;
      \?) die "unknown option: -$OPTARG (see -h)" ;;
    esac
  done
  shift "$((OPTIND - 1))"

  local file="${1:-}"
  [[ -n "$file" ]] || { usage; die "FILE argument is required"; }
  [[ -f "$file" ]] || die "not a regular file: $file"
  [[ -r "$file" ]] || die "file is not readable: $file"
  [[ "$preview" =~ ^[0-9]+$ && "$preview" -gt 0 ]] || die "-n must be a positive integer (got '$preview')"

  need_cmd wc
  need_cmd head
  need_cmd tail
  need_cmd awk

  local lines words chars longest
  lines="$(wc -l < "$file")"
  words="$(wc -w < "$file")"
  chars="$(wc -c < "$file")"
  longest="$(awk '{ if (length($0) > max) max = length($0) } END { print max + 0 }' "$file")"

  # Trim any stray whitespace from wc output (some platforms pad it).
  lines="${lines//[[:space:]]/}"
  words="${words//[[:space:]]/}"
  chars="${chars//[[:space:]]/}"

  banner "Text statistics"
  c_info "File:           $file"
  printf '  %-16s %s\n' "Lines:" "$lines"
  printf '  %-16s %s\n' "Words:" "$words"
  printf '  %-16s %s\n' "Characters:" "$chars"
  printf '  %-16s %s\n' "Longest line:" "$longest"

  banner "Head (first $preview lines)"
  head -n "$preview" -- "$file" || true

  banner "Tail (last $preview lines)"
  tail -n "$preview" -- "$file" || true

  hr
  c_ok "Done: $file"
}

main "$@"
