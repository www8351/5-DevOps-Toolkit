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
  -m             sort by memory usage (default: CPU)
  -n COUNT       number of processes to show (default: 10)
  -h, --help     show this help and exit

Examples:
  $0                 # top 10 by CPU
  $0 -m              # top 10 by memory
  $0 -m -n 5         # top 5 by memory
EOF
}

main() {
  local by_mem=0 count=10

  while getopts ":mn:h-:" opt; do
    case "$opt" in
      m) by_mem=1 ;;
      n) count="$OPTARG" ;;
      h) usage; exit 0 ;;
      -) # support the long --help form
         [[ "$OPTARG" == "help" ]] && { usage; exit 0; }
         die "unknown option: --$OPTARG (try -h)" ;;
      :) die "option -$OPTARG requires an argument (try -h)" ;;
      \?) die "unknown option: -$OPTARG (try -h)" ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ "$count" =~ ^[1-9][0-9]*$ ]] || die "COUNT must be a positive integer, got: $count"

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
