#!/usr/bin/env bash
#
# pingsweep.sh — ping a list of hosts and print an up/down table
#   commands showcased: ping -c1 -W1
#
# Usage: ./pingsweep.sh [--json] <host> [host...]  | -f FILE
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
  -f, --file FILE  read hosts from FILE (one host per line, # comments ok)
  --json           print one JSON document instead of the table
  -h, --help       show this help and exit

Each host is pinged once (ping -c1 -W1). Read-only.

Exit status: 0 when every host answers, 1 when any host is down (ready for
cron or a CI check), 2 on a usage error.
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
  local -a hosts=()
  local file="" json=0

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file) need_arg "$@"; file="$2"; shift 2 ;;
      --json)    json=1; shift ;;
      --) shift; hosts+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
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

  [[ "${#hosts[@]}" -gt 0 ]] || usage_error "no hosts given (provide host... or -f FILE)"

  # Checked after parsing so -h works without ping installed.
  need_cmd ping

  if [[ "$json" -eq 0 ]]; then
    banner "Ping sweep (${#hosts[@]} host(s))"
    printf '%-30s  %-6s  %s\n' "HOST" "STATE" "RTT(ms)"
    hr
  fi

  local up=0 down=0 host rtt
  local -a records=()
  for host in "${hosts[@]}"; do
    if rtt="$(ping_host "$host")"; then
      up=$((up + 1))
      if [[ "$json" -eq 1 ]]; then
        records+=("$(printf '{"host":%s,"up":true,"rtt_ms":%s}' "$(json_str "$host")" "$(json_num "$rtt")")")
      else
        printf '%-30s  ' "$host"
        c_ok "$(printf '%-6s  %s' "UP" "${rtt:-?}")"
      fi
    else
      down=$((down + 1))
      if [[ "$json" -eq 1 ]]; then
        records+=("$(printf '{"host":%s,"up":false,"rtt_ms":null}' "$(json_str "$host")")")
      else
        printf '%-30s  ' "$host"
        c_fail "$(printf '%-6s  %s' "DOWN" "-")"
      fi
    fi
  done

  if [[ "$json" -eq 1 ]]; then
    local joined
    joined="$(IFS=,; printf '%s' "${records[*]}")"
    printf '{"tool":"pingsweep","ok":%s,"hosts":[%s]}\n' \
      "$([[ "$down" -eq 0 ]] && echo true || echo false)" "$joined"
  else
    hr
    c_info "summary: ${up} up, ${down} down, ${#hosts[@]} total"
  fi
  [[ "$down" -eq 0 ]]
}

main "$@"
