#!/usr/bin/env bash
#
# diskwatch.sh — flag mounted filesystems above a usage threshold
#   commands showcased: df, tail, read
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

Walks the real filesystems from 'df -hP' and reports each mount point's
usage. Mounts at or above the threshold are flagged. Pseudo filesystems and
read-only images that are always full (tmpfs, overlay, snap loop mounts)
are skipped.

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

  c_info "Checking filesystem usage against ${threshold}% threshold"
  hr

  local over=0 fs size used _avail use_pct mount

  # df -hP gives portable, single-line-per-fs output (POSIX -P), so the first
  # five columns line up predictably. read puts everything after them into
  # mount, which keeps mount points that contain spaces intact. The header is
  # skipped with tail -n +2.
  while read -r fs size used _avail use_pct mount; do
    # Skip pseudo filesystems and read-only images that always report 100%:
    # snap packages (/dev/loop*) and macOS automount maps.
    case "$fs" in
      tmpfs|devtmpfs|udev|overlay|none|map|/dev/loop*) continue ;;
    esac

    # Use% sits in column 5; strip the trailing '%' for arithmetic.
    use_pct="${use_pct%\%}"
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
