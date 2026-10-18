#!/usr/bin/env bash
#
# httpcheck.sh — check HTTP status code and response time for one or more URLs
#   commands showcased: curl -o /dev/null -w, wget
#
# Usage: ./httpcheck.sh [-t TIMEOUT] [--json] <url> [url...]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
httpcheck.sh — check HTTP status code and response time for one or more URLs

Usage: $0 [-t TIMEOUT] [--json] <url> [url...]

Options:
  -t, --timeout SECS  per-request timeout in seconds (default 10)
  --json              print one JSON document instead of the table
  -h, --help          show this help and exit

Uses curl when available, otherwise falls back to wget --spider. Read-only.

Exit status: 0 when every URL answers 2xx/3xx, 1 otherwise (so the script
works as a cron or CI health check), 2 on a usage error.
EOF
}

# probe_url URL TIMEOUT — set PROBE_CODE (e.g. 200, or 2xx/3xx from the wget
# fallback, empty when unreachable) and PROBE_RTT (seconds, may be empty).
# Returns 0 when the answer is 2xx/3xx.
probe_url() {
  local url="$1" timeout="$2" out=""
  PROBE_CODE="" PROBE_RTT=""

  if command -v curl >/dev/null 2>&1; then
    if out="$(curl -s -o /dev/null \
        -w '%{http_code} %{time_total}' \
        --max-time "$timeout" "$url" 2>/dev/null)"; then
      PROBE_CODE="${out%% *}"
      PROBE_RTT="${out##* }"
    fi
  else
    # wget fallback: --spider returns success on 2xx/3xx, but cannot
    # easily report the numeric code, so we infer up/down only.
    if wget -q --spider --timeout="$timeout" --tries=1 "$url" 2>/dev/null; then
      PROBE_CODE="2xx/3xx"
    fi
  fi
  [[ "$PROBE_CODE" == "000" ]] && PROBE_CODE=""

  # "2xx/3xx" (the wget fallback marker) is already matched by 2*.
  case "$PROBE_CODE" in
    2*|3*) return 0 ;;
    *)     return 1 ;;
  esac
}

# print_row URL OK — one aligned, coloured table row from the PROBE_* values.
print_row() {
  local url="$1" ok="$2" rtt_disp="-"
  [[ -n "$PROBE_RTT" ]] && rtt_disp="${PROBE_RTT}s"
  printf '%-45s  ' "$url"
  if [[ -z "$PROBE_CODE" ]]; then
    c_fail "$(printf '%-9s  %s' "FAIL" "-")"
  elif [[ "$ok" -eq 1 ]]; then
    c_ok "$(printf '%-9s  %s' "$PROBE_CODE" "$rtt_disp")"
  else
    c_fail "$(printf '%-9s  %s' "$PROBE_CODE" "$rtt_disp")"
  fi
}

main() {
  local timeout=10 json=0
  local -a urls=()

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--timeout) need_arg "$@"; timeout="$2"; shift 2 ;;
      --json)       json=1; shift ;;
      --) shift; urls+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) urls+=("$1"); shift ;;
    esac
  done

  [[ "$timeout" =~ ^[1-9][0-9]*$ ]] || usage_error "--timeout must be a positive integer (got '$timeout')"
  [[ "${#urls[@]}" -gt 0 ]] || usage_error "no URLs given (provide url...)"

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    die "need curl or wget on PATH"
  fi

  if [[ "$json" -eq 0 ]]; then
    banner "HTTP check (timeout ${timeout}s)"
    printf '%-45s  %-9s  %s\n' "URL" "STATUS" "TIME"
    hr
  fi

  local good=0 bad=0 url ok status
  local -a records=()
  for url in "${urls[@]}"; do
    if probe_url "$url" "$timeout"; then
      ok=1; good=$((good + 1))
    else
      ok=0; bad=$((bad + 1))
    fi
    if [[ "$json" -eq 1 ]]; then
      # Only a real three-digit code is a number; the wget marker is null.
      status=null
      [[ "$PROBE_CODE" =~ ^[0-9]{3}$ ]] && status="$((10#$PROBE_CODE))"
      records+=("$(printf '{"url":%s,"status":%s,"time_s":%s,"ok":%s}' \
        "$(json_str "$url")" "$status" "$(json_num "$PROBE_RTT")" \
        "$([[ "$ok" -eq 1 ]] && echo true || echo false)")")
    else
      print_row "$url" "$ok"
    fi
  done

  if [[ "$json" -eq 1 ]]; then
    local joined
    joined="$(IFS=,; printf '%s' "${records[*]}")"
    printf '{"tool":"httpcheck","timeout_s":%s,"ok":%s,"results":[%s]}\n' \
      "$timeout" "$([[ "$bad" -eq 0 ]] && echo true || echo false)" "$joined"
  else
    hr
    c_info "summary: ${good} ok, ${bad} failed, ${#urls[@]} total"
  fi
  [[ "$bad" -eq 0 ]]
}

main "$@"
