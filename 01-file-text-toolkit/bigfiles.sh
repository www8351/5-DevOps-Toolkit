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
  -n, --top N          show only the top N files (default: 15)
  -s, --size MINSIZE   only consider files matching find -size MINSIZE (e.g. +10M)
  -h, --help           show this help and exit

Exit status: 0 on success (also when nothing matches), 1 if PATH is not a
directory, 2 on a usage error.

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
  help_requested "$@" && { usage; exit 0; }

  local top=15 minsize=""
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--top)  need_arg "$@"; top="$2"; shift 2 ;;
      -s|--size) need_arg "$@"; minsize="$2"; shift 2 ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one PATH (got ${#args[@]} arguments)"
  [[ "$top" =~ ^[1-9][0-9]*$ ]] || usage_error "--top must be a positive integer (got '$top')"
  local target="${args[0]:-.}"
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
  # if it is unsupported, fall back to 'du -b' via -exec. Support is probed on
  # its own: find also exits 1 for an unreadable subdirectory, and that must
  # not be mistaken for a missing -printf. Unreadable parts are skipped.
  local raw=""
  if find "$target" -maxdepth 0 -printf '' >/dev/null 2>&1; then
    raw="$(find "${find_args[@]}" -printf '%s\t%p\n' 2>/dev/null || true)"
  else
    need_cmd du
    c_warn "find -printf unsupported here; falling back to du -b"
    raw="$(find "${find_args[@]}" -exec du -b {} + 2>/dev/null || true)"
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
  done < <(printf '%s\n' "$raw" | sort -rn | awk -v n="$top" 'NR <= n')

  hr
  c_ok "Listed up to $top largest file(s) under $target"
}

main "$@"
