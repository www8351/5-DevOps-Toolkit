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
  -t TIMEOUT     per-request timeout in seconds (default 10)
  -h, --help     show this help and exit

Uses curl when available, otherwise falls back to wget --spider. Read-only.
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

  case "$code" in
    2*|3*|"2xx/3xx") c_ok  "$(printf '%-9s  %s' "$code" "$rtt_disp")"; return 0 ;;
    *)               c_err "$(printf '%-9s  %s' "$code" "$rtt_disp")"; return 1 ;;
  esac
}

main() {
  local timeout=10
  local -a urls=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -t)
        [[ $# -ge 2 ]] || die "-t requires a TIMEOUT argument"
        timeout="$2"
        [[ "$timeout" =~ ^[0-9]+$ ]] || die "timeout must be a positive integer: $timeout"
        shift 2
        ;;
      -*) die "unknown option: $1 (try -h)" ;;
      *) urls+=("$1"); shift ;;
    esac
  done

  [[ "${#urls[@]}" -gt 0 ]] || die "no URLs given (provide url... ; try -h)"

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
}

main "$@"
