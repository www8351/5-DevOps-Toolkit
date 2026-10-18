#!/usr/bin/env bash
#
# mkswap.sh — create and enable a swapfile, optionally persisting in fstab
#   commands showcased: fallocate, dd, chmod, mkswap, swapon, /etc/fstab
#
# Usage: sudo ./mkswap.sh -s SIZE [-f FILE] [--persist] [--dry-run] [--yes]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
mkswap.sh — create and enable a swapfile, optionally persisting in fstab

Usage: sudo $0 -s SIZE [-f FILE] [--persist] [--dry-run] [--yes]

Creates a swapfile of the requested SIZE, secures it (chmod 600), formats
it as swap, and enables it. With --persist it also adds an /etc/fstab entry
so the swapfile survives reboots.

Options:
  -s, --size SIZE  swapfile size with a K, M or G unit, at least 1M,
                   e.g. 512M, 2G (required)
  -f, --file FILE  absolute swapfile path (default: /swapfile)
  --persist        append an /etc/fstab entry so swap is enabled on boot
  --dry-run        print the mutating commands instead of running them
  --yes            skip the confirmation prompt (use in CI only)
  -h, --help       show this help and exit

Examples:
  sudo $0 -s 2G
  sudo $0 --size 1G --file /var/swapfile --persist
  $0 --dry-run --size 4G --persist     # preview, no root needed

The same toggles exist as DRY_RUN=1 and ASSUME_YES=1. With sudo, put them
after it (sudo DRY_RUN=1 $0 ...): sudo resets the environment, so a
variable set before it never reaches the script. --dry-run avoids that trap.

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  local size="" file="/swapfile" persist=0

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -s|--size) need_arg "$@"; size="$2"; shift 2 ;;
      -f|--file) need_arg "$@"; file="$2"; shift 2 ;;
      --persist) persist=1; shift ;;
      --dry-run) export DRY_RUN=1; shift ;;
      --yes)     export ASSUME_YES=1; shift ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  [[ -n "$size" ]] || usage_error "missing required option -s/--size SIZE"
  # The unit is mandatory: fallocate would read a bare number as bytes while
  # the dd fallback reads it as MiB, so 1048576 could mean 1 MiB or 1 TiB.
  # At most 9 digits keeps the KiB arithmetic far from 64-bit overflow.
  [[ "$size" =~ ^[1-9][0-9]{0,8}[KkMmGg]$ ]] \
    || usage_error "invalid SIZE '$size' (needs a K, M or G unit, e.g. 512M, 2G)"
  local kib
  kib="$(size_to_kib "$size")"
  # mkswap rejects tiny files, so refuse before anything is allocated.
  [[ "$kib" -ge 1024 ]] || usage_error "SIZE '$size' is too small (minimum 1M)"
  # swapon and the fstab entry both need an absolute path.
  [[ "$file" == /* ]] || usage_error "swapfile path must be absolute: $file"

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

  confirm_or_abort "Proceed with creating and enabling this swapfile?"

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
