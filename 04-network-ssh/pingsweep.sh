#!/usr/bin/env bash
#
# pingsweep.sh — ping a list of hosts and print an up/down table
#   commands showcased: ping -c1 -W1
#
# Usage: ./pingsweep.sh <host> [host...]
#        ./pingsweep.sh -f <file>
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
pingsweep.sh — ping a list of hosts and print an up/down table

Usage: $0 <host> [host...]
       $0 -f <file>

Options:
  -f FILE        read hosts from FILE (one host per line, # comments ok)
  -h, --help     show this help and exit

Each host is pinged once (ping -c1 -W1). Read-only.
EOF
}

# Ping one host; on success echo the round-trip time, return 0. Else return 1.
ping_host() {
  local host="$1" out=""
  if out="$(ping -c1 -W1 "$host" 2>/dev/null)"; then
    local rtt
    rtt="$(printf '%s\n' "$out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n1)"
    [[ -n "$rtt" ]] && printf '%s' "$rtt"
    return 0
  fi
  return 1
}

main() {
  need_cmd ping

  local -a hosts=()
  local file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -f)
        [[ $# -ge 2 ]] || die "-f requires a FILE argument"
        file="$2"
        shift 2
        ;;
      -*) die "unknown option: $1 (try -h)" ;;
      *) hosts+=("$1"); shift ;;
    esac
  done

  if [[ -n "$file" ]]; then
    [[ -f "$file" ]] || die "file not found: $file"
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%#*}"
      line="${line//[[:space:]]/}"
      [[ -n "$line" ]] && hosts+=("$line")
    done <"$file"
  fi

  [[ "${#hosts[@]}" -gt 0 ]] || die "no hosts given (provide host... or -f FILE)"

  banner "Ping sweep (${#hosts[@]} host(s))"
  printf '%-30s  %-6s  %s\n' "HOST" "STATE" "RTT(ms)"
  hr

  local up=0 down=0 host rtt
  for host in "${hosts[@]}"; do
    if rtt="$(ping_host "$host")"; then
      up=$((up + 1))
      printf '%-30s  ' "$host"
      c_ok "$(printf '%-6s  %s' "UP" "${rtt:-?}")"
    else
      down=$((down + 1))
      printf '%-30s  ' "$host"
      c_err "$(printf '%-6s  %s' "DOWN" "-")"
    fi
  done

  hr
  c_info "summary: ${up} up, ${down} down, ${#hosts[@]} total"
}

main "$@"
