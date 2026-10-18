#!/usr/bin/env bash
#
# mkswap.sh — create and enable a swapfile, optionally persisting in fstab
#   commands showcased: fallocate, dd, chmod, mkswap, swapon, /etc/fstab
#
# Usage: sudo ./mkswap.sh -s SIZE [-f FILE] [--persist]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
mkswap.sh — create and enable a swapfile, optionally persisting in fstab

Usage: sudo $0 -s SIZE [-f FILE] [--persist]

Creates a swapfile of the requested SIZE, secures it (chmod 600), formats
it as swap, and enables it. With --persist it also adds an /etc/fstab entry
so the swapfile survives reboots.

Options:
  -s SIZE        swapfile size, e.g. 512M, 2G (required)
  -f FILE        swapfile path (default: /swapfile)
  --persist      append an /etc/fstab entry so swap is enabled on boot
  -h, --help     show this help and exit

Honoured environment toggles:
  DRY_RUN=1      print the mutating commands instead of running them
  ASSUME_YES=1   skip the confirmation prompt (use in CI only)

Examples:
  sudo $0 -s 2G
  sudo $0 -s 1G -f /var/swapfile --persist
  DRY_RUN=1 sudo $0 -s 4G --persist
EOF
}

main() {
  local size="" file="/swapfile" persist=0

  # Hand-rolled parser so we can support the long --persist / --help flags
  # alongside the short -s / -f options.
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s) [[ $# -ge 2 ]] || die "option -s requires an argument (try -h)"
          size="$2"; shift 2 ;;
      -f) [[ $# -ge 2 ]] || die "option -f requires an argument (try -h)"
          file="$2"; shift 2 ;;
      --persist) persist=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1 (try -h)" ;;
    esac
  done

  [[ -n "$size" ]] || die "missing required option -s SIZE (try -h)"
  # Accept sizes like 512M, 2G, 1048576 (bytes) — a digit run with optional unit.
  [[ "$size" =~ ^[0-9]+([KkMmGg])?$ ]] \
    || die "invalid SIZE '$size' (examples: 512M, 2G)"

  require_root

  need_cmd mkswap
  need_cmd swapon
  need_cmd chmod

  # Guard: never clobber an existing path or re-add an active swapfile.
  [[ -e "$file" ]] && die "refusing to overwrite existing path: $file"
  if swapon --show 2>/dev/null | awk '{print $1}' | grep -Fxq "$file"; then
    die "swap already active for: $file"
  fi

  c_info "About to create a ${size} swapfile at ${file}"
  [[ "$persist" -eq 1 ]] && c_info "It will be persisted in /etc/fstab"

  confirm "Proceed with creating and enabling this swapfile?" \
    || die "aborted by user"

  # Allocate the file. fallocate is instant; fall back to dd where the
  # filesystem (e.g. some older ext/zfs setups) does not support fallocate.
  if command -v fallocate >/dev/null 2>&1; then
    if ! run fallocate -l "$size" "$file"; then
      c_warn "fallocate failed — falling back to dd"
      dd_allocate "$size" "$file"
    fi
  else
    c_warn "fallocate not found — using dd"
    dd_allocate "$size" "$file"
  fi

  run chmod 600 "$file"
  run mkswap "$file"
  run swapon "$file"

  if [[ "$persist" -eq 1 ]]; then
    persist_fstab "$file"
  fi

  c_ok "swapfile ready: $file"
  command -v swapon >/dev/null 2>&1 && run swapon --show
}

# dd_allocate SIZE FILE — write a zero-filled file when fallocate is unavailable.
# Converts a K/M/G suffixed SIZE into a whole number of 1 MiB blocks.
dd_allocate() {
  local size="$1" file="$2" mib
  need_cmd dd
  mib="$(size_to_mib "$size")"
  [[ "$mib" -ge 1 ]] || die "computed swap size is under 1 MiB: $size"
  run dd if=/dev/zero of="$file" bs=1M count="$mib" status=progress
}

# size_to_mib SIZE — echo the size expressed in whole mebibytes.
size_to_mib() {
  local s="$1" num unit
  num="${s%[KkMmGg]}"
  unit="${s#"$num"}"
  case "$unit" in
    K|k) echo $(( (num + 1023) / 1024 )) ;;   # round K up to whole MiB
    M|m|"") echo "$num" ;;
    G|g) echo $(( num * 1024 )) ;;
    *) die "cannot convert size: $s" ;;
  esac
}

# persist_fstab FILE — add a swap entry to /etc/fstab if not already present.
persist_fstab() {
  local file="$1" fstab="/etc/fstab" entry
  entry="$file none swap sw 0 0"

  if [[ -e "$fstab" ]] && grep -qE "^[[:space:]]*${file//\//\\/}[[:space:]]" "$fstab"; then
    c_warn "an /etc/fstab entry for $file already exists — not adding another"
    return 0
  fi

  c_info "Appending to /etc/fstab: $entry"
  run sh -c 'printf "%s\n" "$1" >> "$2"' _ "$entry" "$fstab"
  [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "added /etc/fstab entry"
}

main "$@"
