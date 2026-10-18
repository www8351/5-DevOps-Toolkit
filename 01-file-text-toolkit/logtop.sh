#!/usr/bin/env bash
#
# logtop.sh — top talkers in a log: most frequent value of a chosen field/word
#   commands showcased: grep, awk, sort, uniq, wc
#
# Usage: ./logtop.sh [-k FIELD] [-d DELIM] [-n N] [-g PATTERN] FILE
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
  -k, --field N      awk field number to count (default: 1)
  -d, --delim DELIM  field delimiter passed to awk -F (default: whitespace)
  -n, --top N        show only the top N results (default: 10)
  -g, --grep PATTERN grep pre-filter; only lines matching PATTERN are counted
  -h, --help         show this help and exit

Deprecated (still work, removed in 2.0.0): -f FIELD (use -k), -p PATTERN (use -g).

Exit status: 0 on success, 1 if FILE cannot be read, 2 on a usage error.

Read-only: this script never modifies anything.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local field=1 delim="" top=10 pattern=""
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -k|--field) need_arg "$@"; field="$2"; shift 2 ;;
      -f)         deprecated -f -k/--field; need_arg "$@"; field="$2"; shift 2 ;;
      -d|--delim) need_arg "$@"; delim="$2"; shift 2 ;;
      -n|--top)   need_arg "$@"; top="$2"; shift 2 ;;
      -g|--grep)  need_arg "$@"; pattern="$2"; shift 2 ;;
      -p)         deprecated -p -g/--grep; need_arg "$@"; pattern="$2"; shift 2 ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "${#args[@]}" -eq 1 ]] || usage_error "expected exactly one FILE (got ${#args[@]} arguments)"
  [[ "$field" =~ ^[1-9][0-9]*$ ]] || usage_error "--field must be a positive integer (got '$field')"
  [[ "$top" =~ ^[1-9][0-9]*$ ]] || usage_error "--top must be a positive integer (got '$top')"
  local file="${args[0]}"
  [[ -f "$file" ]] || die "not a regular file: $file"
  [[ -r "$file" ]] || die "file is not readable: $file"

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

  # The last awk keeps the top N itself instead of `head`: head would close the
  # pipe early, sort would die of SIGPIPE, and pipefail would abort the script.
  local -a top_n=(awk -v n="$top"
    'NR <= n { c=$1; $1=""; sub(/^ /,""); printf "%-10s | %s\n", c, $0 }')

  printf '%-10s | %s\n' "COUNT" "VALUE"
  hr
  if [[ -n "$pattern" ]]; then
    # grep exits 1 when nothing matches; that is an empty result, not an error.
    { grep -e "$pattern" -- "$file" || [[ $? -eq 1 ]]; } \
      | "${awk_cmd[@]}" \
      | sort \
      | uniq -c \
      | sort -rn \
      | "${top_n[@]}"
  else
    "${awk_cmd[@]}" "$file" \
      | sort \
      | uniq -c \
      | sort -rn \
      | "${top_n[@]}"
  fi

  hr
  c_ok "Lines considered: ${total:-0}"
}

main "$@"
