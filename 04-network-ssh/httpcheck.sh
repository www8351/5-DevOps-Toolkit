#!/usr/bin/env bash
#
# httpcheck.sh — check HTTP status code and response time for one or more URLs
#   commands showcased: curl -o /dev/null -w, wget
#
# Usage: ./httpcheck.sh [-t TIMEOUT] <url> [url...]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
httpcheck.sh — check HTTP status code and response time for one or more URLs

Usage: $0 [-t TIMEOUT] <url> [url...]

Options:
  -t, --timeout SECS  per-request timeout in seconds (default 10)
  -h, --help          show this help and exit

Uses curl when available, otherwise falls back to wget --spider. Read-only.

Exit status: 0 when every URL answers 2xx/3xx, 1 otherwise (so the script
works as a cron or CI health check), 2 on a usage error.
EOF
}

# Print one aligned, coloured result row for a URL.
check_url() {
  local url="$1" timeout="$2"
  local code="" rtt="" out=""

  if command -v curl >/dev/null 2>&1; then
    if out="$(curl -s -o /dev/null \
        -w '%{http_code} %{time_total}' \
        --max-time "$timeout" "$url" 2>/dev/null)"; then
      code="${out%% *}"
      rtt="${out##* }"
    fi
  else
    # wget fallback: --spider returns success on 2xx/3xx, but cannot
    # easily report the numeric code, so we infer up/down only.
    if wget -q --spider --timeout="$timeout" --tries=1 "$url" 2>/dev/null; then
      code="2xx/3xx"
    fi
  fi

  printf '%-45s  ' "$url"
  if [[ -z "$code" || "$code" == "000" ]]; then
    c_err "$(printf '%-9s  %s' "FAIL" "-")"
    return 1
  fi

  local rtt_disp="-"
  [[ -n "$rtt" ]] && rtt_disp="$(printf '%ss' "$rtt")"

  # "2xx/3xx" (the wget fallback marker) is already matched by 2*.
  case "$code" in
    2*|3*) c_ok  "$(printf '%-9s  %s' "$code" "$rtt_disp")"; return 0 ;;
    *)     c_err "$(printf '%-9s  %s' "$code" "$rtt_disp")"; return 1 ;;
  esac
}

main() {
  local timeout=10
  local -a urls=()

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -t|--timeout) need_arg "$@"; timeout="$2"; shift 2 ;;
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

  banner "HTTP check (timeout ${timeout}s)"
  printf '%-45s  %-9s  %s\n' "URL" "STATUS" "TIME"
  hr

  local ok=0 bad=0 url
  for url in "${urls[@]}"; do
    if check_url "$url" "$timeout"; then
      ok=$((ok + 1))
    else
      bad=$((bad + 1))
    fi
  done

  hr
  c_info "summary: ${ok} ok, ${bad} failed, ${#urls[@]} total"
  [[ "$bad" -eq 0 ]]
}

main "$@"
