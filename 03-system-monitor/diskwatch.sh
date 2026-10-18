#!/usr/bin/env bash
#
# diskwatch.sh — flag mounted filesystems above a usage threshold
#   commands showcased: df, tail, read
#
# Usage: ./diskwatch.sh [-w PERCENT] [--json]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
diskwatch.sh — flag mounted filesystems above a usage threshold

Usage: $0 [-w PERCENT] [--json]

Walks the real filesystems from 'df -hP' and reports each mount point's
usage. Mounts at or above the threshold are flagged. Pseudo filesystems and
read-only images that are always full (tmpfs, overlay, snap loop mounts)
are skipped.

Options:
  -w, --warn PERCENT  usage threshold, 1-100 (default: 80)
  --json              print one JSON document instead of the table (sizes in KiB)
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

  local threshold=80 json=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -w|--warn) need_arg "$@"; threshold="$2"; shift 2 ;;
      -t)        deprecated -t -w/--warn; need_arg "$@"; threshold="$2"; shift 2 ;;
      --json)    json=1; shift ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ "$threshold" =~ ^[1-9][0-9]?$|^100$ ]] \
    || usage_error "threshold must be an integer 1-100, got: $threshold"

  need_cmd df

  # Human sizes for people, KiB integers for machines.
  local df_flags="-hP"
  if [[ "$json" -eq 1 ]]; then
    df_flags="-kP"
  else
    c_info "Checking filesystem usage against ${threshold}% threshold"
    hr
  fi

  local over=0 fs size used avail use_pct mount is_over
  local -a records=()

  # df -P gives portable, single-line-per-fs output, so the first five
  # columns line up predictably. read puts everything after them into mount,
  # which keeps mount points that contain spaces intact. The header is
  # skipped with tail -n +2.
  while read -r fs size used avail use_pct mount; do
    # Skip pseudo filesystems and read-only images that always report 100%:
    # snap packages (/dev/loop*) and macOS automount maps.
    case "$fs" in
      tmpfs|devtmpfs|udev|overlay|none|map|/dev/loop*) continue ;;
    esac

    # Use% sits in column 5; strip the trailing '%' for arithmetic.
    use_pct="${use_pct%\%}"
    # Some pseudo mounts report '-' for usage; ignore anything non-numeric.
    [[ "$use_pct" =~ ^[0-9]+$ ]] || continue

    is_over=false
    if [[ "$use_pct" -ge "$threshold" ]]; then
      is_over=true
      over=1
    fi

    if [[ "$json" -eq 1 ]]; then
      records+=("$(printf '{"filesystem":%s,"mount":%s,"size_kib":%s,"used_kib":%s,"available_kib":%s,"use_pct":%s,"over":%s}' \
        "$(json_str "$fs")" "$(json_str "$mount")" "$(json_num "$size")" "$(json_num "$used")" \
        "$(json_num "$avail")" "$use_pct" "$is_over")")
    elif [[ "$is_over" == true ]]; then
      c_fail "$(printf '%-22s %4s%%  used %s/%s' "$mount" "$use_pct" "$used" "$size")"
    else
      c_ok "$(printf '%-22s %4s%%  used %s/%s' "$mount" "$use_pct" "$used" "$size")"
    fi
  done < <(df "$df_flags" | tail -n +2)

  if [[ "$json" -eq 1 ]]; then
    local ok=true joined
    [[ "$over" -eq 1 ]] && ok=false
    joined="$(IFS=,; printf '%s' "${records[*]}")"
    printf '{"tool":"diskwatch","warn_pct":%s,"ok":%s,"filesystems":[%s]}\n' \
      "$threshold" "$ok" "$joined"
    exit "$over"
  fi

  hr
  if [[ "$over" -eq 1 ]]; then
    c_warn "one or more filesystems are at/above ${threshold}%"
    exit 1
  fi
  c_ok "all filesystems are below ${threshold}%"
}

main "$@"
