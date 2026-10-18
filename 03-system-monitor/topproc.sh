#!/usr/bin/env bash
#
# topproc.sh — top-N processes by CPU or memory
#   commands showcased: ps, sort, head
#
# Usage: ./topproc.sh [-m] [-n COUNT]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
topproc.sh — top-N processes by CPU or memory

Usage: $0 [-m] [-n COUNT]

Options:
  -m, --mem          sort by memory usage (default: CPU)
  -n, --top COUNT    number of processes to show (default: 10)
  -h, --help         show this help and exit

Exit status: 0 on success, 2 on a usage error.

Examples:
  $0                     # top 10 by CPU
  $0 --mem               # top 10 by memory
  $0 --mem --top 5       # top 5 by memory
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local by_mem=0 count=10
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mem) by_mem=1; shift ;;
      -n|--top) need_arg "$@"; count="$2"; shift 2 ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ "$count" =~ ^[1-9][0-9]*$ ]] || usage_error "--top must be a positive integer, got: $count"

  need_cmd ps

  local sort_key col label
  if [[ "$by_mem" -eq 1 ]]; then
    sort_key="-%mem"; col=4; label="memory"
  else
    sort_key="-%cpu"; col=3; label="CPU"
  fi

  c_info "Top $count processes by $label"
  hr

  # Prefer ps's own --sort (GNU/procps). If unsupported (e.g. BusyBox),
  # fall back to a manual numeric sort on the relevant %CPU/%MEM column.
  if ps aux --sort="$sort_key" >/dev/null 2>&1; then
    # Header line first, then the next "$count" rows.
    # `|| true` absorbs SIGPIPE (141) when head closes the pipe early under pipefail.
    ps aux --sort="$sort_key" | head -n "$((count + 1))" || true
  else
    c_warn "ps --sort unsupported — falling back to manual sort"
    {
      ps aux | head -n 1 || true
      ps aux | tail -n +2 | sort -k"${col}" -rn | head -n "$count" || true
    }
  fi
}

main "$@"
