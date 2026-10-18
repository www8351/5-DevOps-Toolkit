#!/usr/bin/env bash
#
# diskwatch.sh — flag mounted filesystems above a usage threshold
#   commands showcased: df, tail, read
#
# Usage: ./diskwatch.sh [-w PERCENT]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
diskwatch.sh — flag mounted filesystems above a usage threshold

Usage: $0 [-w PERCENT]

Walks the real filesystems from 'df -hP' and reports each mount point's
usage. Mounts at or above the threshold are flagged. Pseudo filesystems and
read-only images that are always full (tmpfs, overlay, snap loop mounts)
are skipped.

Options:
  -w, --warn PERCENT  usage threshold, 1-100 (default: 80)
  -h, --help          show this help and exit

Deprecated (still works, removed in 2.0.0): -t PERCENT (use -w/--warn).

Exit status: 0 when every mount is below the threshold, 1 if ANY mount is
at or above it (ready for cron or a CI health check), 2 on a usage error.

Examples:
  $0                 # warn at 80% and above
  $0 --warn 90       # warn at 90% and above
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local threshold=80
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -w|--warn) need_arg "$@"; threshold="$2"; shift 2 ;;
      -t)        deprecated -t -w/--warn; need_arg "$@"; threshold="$2"; shift 2 ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ "$threshold" =~ ^[1-9][0-9]?$|^100$ ]] \
    || usage_error "threshold must be an integer 1-100, got: $threshold"

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
