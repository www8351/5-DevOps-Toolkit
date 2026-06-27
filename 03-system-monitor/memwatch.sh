#!/usr/bin/env bash
#
# memwatch.sh — RAM and swap usage report with percentages
#   commands showcased: free, swapon, awk, /proc/meminfo
#
# Usage: ./memwatch.sh [-b]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
memwatch.sh — RAM and swap usage report with percentages

Usage: $0 [-b]

Shows a human-readable memory/swap table, computes the percentage of RAM
and swap currently in use, and lists any active swap devices.

Options:
  -b             show the headline table in raw bytes (free -b) instead of -h
  -h, --help     show this help and exit
EOF
}

# have CMD — true if an optional command is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

main() {
  local raw_bytes=0

  while getopts ":bh-:" opt; do
    case "$opt" in
      b) raw_bytes=1 ;;
      h) usage; exit 0 ;;
      -) [[ "$OPTARG" == "help" ]] && { usage; exit 0; }
         die "unknown option: --$OPTARG (try -h)" ;;
      \?) die "unknown option: -$OPTARG (try -h)" ;;
    esac
  done
  shift $((OPTIND - 1))

  need_cmd free
  need_cmd awk

  banner "Memory & Swap"
  if [[ "$raw_bytes" -eq 1 ]]; then
    free -b
  else
    free -hlt
  fi
  echo

  # Compute percentages from byte-accurate output (free -b) so the maths is
  # exact rather than rounded human-readable values. The 'Mem:' and 'Swap:'
  # rows expose total (col 2) and used (col 3).
  local mem_pct swap_pct
  mem_pct="$(free -b | awk '/^Mem:/ {if ($2 > 0) printf "%.1f", $3/$2*100; else print "0.0"}')"
  swap_pct="$(free -b | awk '/^Swap:/ {if ($2 > 0) printf "%.1f", $3/$2*100; else print "0.0"}')"

  c_info "RAM used:  ${mem_pct}%"
  c_info "Swap used: ${swap_pct}%"
  echo

  # /proc/meminfo gives MemAvailable, the kernel's best estimate of memory
  # claimable without swapping — more useful than free+buffers on modern hosts.
  if [[ -r /proc/meminfo ]]; then
    local avail_kb
    avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
    [[ -n "$avail_kb" ]] \
      && c_info "MemAvailable: $(awk -v kb="$avail_kb" 'BEGIN {printf "%.0f MiB", kb/1024}')"
  else
    c_warn "/proc/meminfo not readable — skipping MemAvailable"
  fi
  echo

  banner "Active swap devices"
  if have swapon; then
    local swap_out
    swap_out="$(swapon --show 2>/dev/null || true)"
    if [[ -n "$swap_out" ]]; then
      printf '%s\n' "$swap_out"
    else
      c_warn "no active swap devices"
    fi
  else
    c_warn "swapon not found — skipping swap device list"
  fi
}

main "$@"
