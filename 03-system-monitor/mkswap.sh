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
  -s SIZE        swapfile size with a K, M or G unit, at least 1M,
                 e.g. 512M, 2G (required)
  -f FILE        absolute swapfile path (default: /swapfile)
  --persist      append an /etc/fstab entry so swap is enabled on boot
  -h, --help     show this help and exit

Honoured environment toggles:
  DRY_RUN=1      print the mutating commands instead of running them
  ASSUME_YES=1   skip the confirmation prompt (use in CI only)

Examples:
  sudo $0 -s 2G
  sudo $0 -s 1G -f /var/swapfile --persist
  sudo DRY_RUN=1 $0 -s 4G --persist

Put DRY_RUN=1 after sudo: sudo resets the environment, so a variable set
before it never reaches the script. A normal user can also preview with
DRY_RUN=1 and no sudo at all.
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
  # The unit is mandatory: fallocate would read a bare number as bytes while
  # the dd fallback reads it as MiB, so 1048576 could mean 1 MiB or 1 TiB.
  # At most 9 digits keeps the KiB arithmetic far from 64-bit overflow.
  [[ "$size" =~ ^[1-9][0-9]{0,8}[KkMmGg]$ ]] \
    || die "invalid SIZE '$size' (needs a K, M or G unit, e.g. 512M, 2G)"
  local kib
  kib="$(size_to_kib "$size")"
  # mkswap rejects tiny files, so refuse before anything is allocated.
  [[ "$kib" -ge 1024 ]] || die "SIZE '$size' is too small (minimum 1M)"
  # swapon and the fstab entry both need an absolute path.
  [[ "$file" == /* ]] || die "swapfile path must be absolute: $file"

  require_root

  need_cmd mkswap
  need_cmd swapon
  need_cmd chmod

  # Guard: never clobber an existing path or re-add an active swapfile. -L
  # also catches a dangling symlink, which root would otherwise follow.
  if [[ -e "$file" || -L "$file" ]]; then
    die "refusing to overwrite existing path: $file"
  fi
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
      dd_allocate "$kib" "$file"
    fi
  else
    c_warn "fallocate not found — using dd"
    dd_allocate "$kib" "$file"
  fi

  run chmod 600 "$file"
  run mkswap "$file"
  run swapon "$file"

  if [[ "$persist" -eq 1 ]]; then
    persist_fstab "$file"
  fi

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "dry run finished: nothing was changed"
  else
    c_ok "swapfile ready: $file"
    swapon --show
  fi
}

# dd_allocate KIB FILE — write a zero-filled file when fallocate is unavailable.
# Writes exactly KIB KiB, the same size fallocate would have made.
dd_allocate() {
  local kib="$1" file="$2"
  need_cmd dd
  if (( kib % 1024 == 0 )); then
    run dd if=/dev/zero of="$file" bs=1M count="$(( kib / 1024 ))" status=progress
  else
    run dd if=/dev/zero of="$file" bs=1K count="$kib" status=progress
  fi
}

# size_to_kib SIZE — echo a K/M/G suffixed SIZE in KiB. The 10# prefix keeps
# bash from reading digits as octal.
size_to_kib() {
  local s="$1" num unit
  num="${s%[KkMmGg]}"
  unit="${s#"$num"}"
  case "$unit" in
    K|k) echo $(( 10#$num )) ;;
    M|m) echo $(( 10#$num * 1024 )) ;;
    G|g) echo $(( 10#$num * 1024 * 1024 )) ;;
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
