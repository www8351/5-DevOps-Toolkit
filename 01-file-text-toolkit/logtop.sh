#!/usr/bin/env bash
#
# logtop.sh — top talkers in a log: most frequent value of a chosen field/word
#   commands showcased: grep, awk, sort, uniq, wc
#
# Usage: ./logtop.sh [-f FIELD] [-d DELIM] [-n N] [-p PATTERN] FILE
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
logtop.sh — top talkers in a log: most frequent value of a chosen field/word

Usage: $0 [options] FILE

Arguments:
  FILE           log file to analyse (required)

Options:
  -f FIELD       awk field number to count (default: 1)
  -d DELIM       field delimiter passed to awk -F (default: whitespace)
  -n N           show only the top N results (default: 10)
  -p PATTERN     grep pre-filter; only lines matching PATTERN are counted
  -h, --help     show this help and exit

Read-only: this script never modifies anything.
EOF
}

main() {
  local field=1
  local delim=""
  local top=10
  local pattern=""

  if [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  local opt
  while getopts ":f:d:n:p:h" opt; do
    case "$opt" in
      f) field="$OPTARG" ;;
      d) delim="$OPTARG" ;;
      n) top="$OPTARG" ;;
      p) pattern="$OPTARG" ;;
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

  [[ "$field" =~ ^[0-9]+$ && "$field" -gt 0 ]] || die "-f must be a positive integer (got '$field')"
  [[ "$top" =~ ^[0-9]+$ && "$top" -gt 0 ]] || die "-n must be a positive integer (got '$top')"

  need_cmd awk
  need_cmd sort
  need_cmd uniq
  need_cmd head
  need_cmd wc
  if [[ -n "$pattern" ]]; then
    need_cmd grep
  fi

  banner "Log top talkers"
  c_info "File:      $file"
  c_info "Field:     $field"
  if [[ -n "$delim" ]]; then
    c_info "Delimiter: '$delim'"
  else
    c_info "Delimiter: whitespace (default)"
  fi
  c_info "Top:       $top"
  if [[ -n "$pattern" ]]; then
    c_info "Filter:    grep '$pattern'"
  fi
  hr

  # Stage 1: optional grep pre-filter. Without a pattern we just cat the file
  # through the rest of the pipeline.
  local total
  if [[ -n "$pattern" ]]; then
    total="$(grep -c -e "$pattern" -- "$file" || true)"
  else
    total="$(wc -l < "$file")"
  fi
  total="${total//[[:space:]]/}"

  # Stage 2: extract the field (honouring -d), then count occurrences.
  # awk reads the (optionally filtered) stream; empty fields are skipped.
  local -a awk_cmd=(awk)
  if [[ -n "$delim" ]]; then
    awk_cmd+=(-F "$delim")
  fi
  awk_cmd+=(-v "f=$field" '{ if (NF >= f && $f != "") print $f }')

  printf '%-10s | %s\n' "COUNT" "VALUE"
  hr
  if [[ -n "$pattern" ]]; then
    grep -e "$pattern" -- "$file" \
      | "${awk_cmd[@]}" \
      | sort \
      | uniq -c \
      | sort -rn \
      | head -n "$top" \
      | awk '{ c=$1; $1=""; sub(/^ /,""); printf "%-10s | %s\n", c, $0 }'
  else
    "${awk_cmd[@]}" "$file" \
      | sort \
      | uniq -c \
      | sort -rn \
      | head -n "$top" \
      | awk '{ c=$1; $1=""; sub(/^ /,""); printf "%-10s | %s\n", c, $0 }'
  fi

  hr
  c_ok "Lines considered: ${total:-0}"
}

main "$@"
