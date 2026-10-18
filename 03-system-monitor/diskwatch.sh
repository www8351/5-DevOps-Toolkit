#!/usr/bin/env bash
#
# diskwatch.sh — flag mounted filesystems above a usage threshold
#   commands showcased: df, awk, tr, tail
#
# Usage: ./diskwatch.sh [-t PERCENT]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
diskwatch.sh — flag mounted filesystems above a usage threshold

Usage: $0 [-t PERCENT]

Walks the real (non-pseudo) filesystems from 'df -hP' and reports each
mount point's usage. Mounts at or above the threshold are flagged.

Exit code is 1 if ANY mount is at/above the threshold, which makes this
script convenient to drop straight into cron or a CI health check.

Options:
  -t PERCENT     usage threshold, 1-100 (default: 80)
  -h, --help     show this help and exit

Examples:
  $0                 # warn at 80% and above
  $0 -t 90           # warn at 90% and above
EOF
}

main() {
  local threshold=80

  while getopts ":t:h-:" opt; do
    case "$opt" in
      t) threshold="$OPTARG" ;;
      h) usage; exit 0 ;;
      -) [[ "$OPTARG" == "help" ]] && { usage; exit 0; }
         die "unknown option: --$OPTARG (try -h)" ;;
      :) die "option -$OPTARG requires an argument (try -h)" ;;
      \?) die "unknown option: -$OPTARG (try -h)" ;;
    esac
  done
  shift $((OPTIND - 1))

  [[ "$threshold" =~ ^[1-9][0-9]?$|^100$ ]] \
    || die "threshold must be an integer 1-100, got: $threshold"

  need_cmd df
  need_cmd awk

  c_info "Checking filesystem usage against ${threshold}% threshold"
  hr

  local over=0 line fs use_pct mount used size

  # df -hP gives portable, single-line-per-fs output (POSIX -P), so each
  # record's columns line up predictably. Skip the header (tail -n +2) and
  # the pseudo filesystems we never want to alarm on.
  while IFS= read -r line; do
    fs="$(echo "$line" | awk '{print $1}')"

    # Skip virtual/pseudo filesystems by source device name.
    case "$fs" in
      tmpfs|devtmpfs|udev|overlay|none) continue ;;
    esac

    size="$(echo "$line"   | awk '{print $2}')"
    used="$(echo "$line"   | awk '{print $3}')"
    mount="$(echo "$line"  | awk '{print $6}')"
    # Use% sits in column 5; strip the trailing '%' for arithmetic.
    use_pct="$(echo "$line" | awk '{print $5}' | tr -d '%')"

    # Some pseudo mounts report '-' for usage; ignore anything non-numeric.
    [[ "$use_pct" =~ ^[0-9]+$ ]] || continue

    if [[ "$use_pct" -ge "$threshold" ]]; then
      c_err "$(printf '%-22s %4s%%  used %s/%s' "$mount" "$use_pct" "$used" "$size")"
      over=1
    else
      c_ok "$(printf '%-22s %4s%%  used %s/%s' "$mount" "$use_pct" "$used" "$size")"
    fi
  done < <(df -hP | tail -n +2)

  hr
  if [[ "$over" -eq 1 ]]; then
    c_warn "one or more filesystems are at/above ${threshold}%"
    exit 1
  fi
  c_ok "all filesystems are below ${threshold}%"
}

main "$@"
