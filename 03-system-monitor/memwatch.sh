#!/usr/bin/env bash
#
# memwatch.sh — RAM and swap usage report with percentages
#   commands showcased: free, swapon, awk, /proc/meminfo
#
# Usage: ./memwatch.sh [-b] [-w PERCENT] [--json]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
memwatch.sh — RAM and swap usage report with percentages

Usage: $0 [-b] [-w PERCENT] [--json]

Shows a human-readable memory/swap table, computes the percentage of RAM
and swap currently in use, and lists any active swap devices.

Options:
  -b, --bytes         show the headline table in raw bytes (free -b) instead of -h
  -w, --warn PERCENT  alert when RAM use is at or above PERCENT (1-100)
  --json              print one JSON document instead of the report
  -h, --help          show this help and exit

Exit status: 0 on success, 1 when RAM use reaches the --warn threshold,
2 on a usage error.
EOF
}

# have CMD — true if an optional command is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

main() {
  help_requested "$@" && { usage; exit 0; }

  local raw_bytes=0 warn="" json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -b|--bytes) raw_bytes=1; shift ;;
      -w|--warn)  need_arg "$@"; warn="$2"; shift 2 ;;
      --json)     json=1; shift ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done
  if [[ -n "$warn" ]]; then
    [[ "$warn" =~ ^[1-9][0-9]?$|^100$ ]] || usage_error "--warn must be an integer 1-100, got: $warn"
  fi

  need_cmd free
  need_cmd awk

  # One byte-accurate read (free -b) gives exact percentages rather than
  # rounded human-readable values. The 'Mem:' and 'Swap:' rows expose total
  # (col 2) and used (col 3). LC_ALL=C pins those labels, which a localized
  # procps would translate.
  local mem_total mem_used swap_total swap_used
  read -r mem_total mem_used swap_total swap_used < <(LC_ALL=C free -b | awk '
    /^Mem:/  { mt = $2; mu = $3 }
    /^Swap:/ { st = $2; su = $3 }
    END { print mt + 0, mu + 0, st + 0, su + 0 }')

  local mem_pct swap_pct
  mem_pct="$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN { printf "%.1f", (t > 0 ? u / t * 100 : 0) }')"
  swap_pct="$(awk -v u="$swap_used" -v t="$swap_total" 'BEGIN { printf "%.1f", (t > 0 ? u / t * 100 : 0) }')"

  # Alert when a threshold was given and RAM use reached it. Compare the exact
  # byte counts: the rounded percentage would fire early (84.96% shows 85.0%).
  local alert=0
  if [[ -n "$warn" ]] \
    && awk -v u="$mem_used" -v t="$mem_total" -v w="$warn" 'BEGIN { exit !(u * 100 >= w * t) }'; then
    alert=1
  fi

  # /proc/meminfo gives MemAvailable, the kernel's best estimate of memory
  # claimable without swapping — more useful than free+buffers on modern hosts.
  local avail_kb=""
  if [[ -r /proc/meminfo ]]; then
    avail_kb="$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)"
  fi

  if [[ "$json" -eq 1 ]]; then
    local ok=true
    [[ "$alert" -eq 1 ]] && ok=false
    printf '{"tool":"memwatch","warn_pct":%s,"ok":%s,"mem":{"total_bytes":%s,"used_bytes":%s,"used_pct":%s},"swap":{"total_bytes":%s,"used_bytes":%s,"used_pct":%s},"mem_available_kib":%s}\n' \
      "$(json_num "$warn")" "$ok" "$mem_total" "$mem_used" "$mem_pct" \
      "$swap_total" "$swap_used" "$swap_pct" "$(json_num "$avail_kb")"
    exit "$alert"
  fi

  banner "Memory & Swap"
  if [[ "$raw_bytes" -eq 1 ]]; then
    free -b
  else
    free -hlt
  fi
  echo

  if [[ "$alert" -eq 1 ]]; then
    c_fail "RAM used:  ${mem_pct}% (at or above the ${warn}% warning)"
  else
    c_info "RAM used:  ${mem_pct}%"
  fi
  c_info "Swap used: ${swap_pct}%"
  echo

  if [[ -n "$avail_kb" ]]; then
    c_info "MemAvailable: $(awk -v kb="$avail_kb" 'BEGIN {printf "%.0f MiB", kb/1024}')"
  else
    c_warn "MemAvailable not available (/proc/meminfo unreadable) — skipped"
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

  exit "$alert"
}

main "$@"
