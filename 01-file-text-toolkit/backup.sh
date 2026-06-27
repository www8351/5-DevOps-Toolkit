#!/usr/bin/env bash
#
# backup.sh — timestamped tar.bz2 backup of a directory, plus an extract mode
#   commands showcased: tar -cjvf, tar -xjvf -C, du, date
#
# Usage: ./backup.sh SRC [DEST_DIR]
#        ./backup.sh --extract ARCHIVE TARGET_DIR
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
backup.sh — timestamped tar.bz2 backup of a directory, plus an extract mode

Usage:
  $0 SRC [DEST_DIR]               create DEST_DIR/<basename>-<timestamp>.tar.bz2
  $0 --extract ARCHIVE TARGET_DIR extract ARCHIVE into TARGET_DIR

Options:
  -h, --help     show this help and exit

Backup mode is non-destructive. Extract mode asks for confirmation and honours
DRY_RUN=1 (print only) and ASSUME_YES=1 (skip the prompt).
EOF
}

do_backup() {
  local src="$1"
  local dest="${2:-.}"

  [[ -e "$src" ]] || die "source does not exist: $src"
  [[ -d "$dest" ]] || die "destination directory does not exist: $dest"

  need_cmd tar
  need_cmd date
  need_cmd du

  local base stamp archive
  base="$(basename "$src")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  archive="${dest%/}/${base}-${stamp}.tar.bz2"

  banner "Create backup"
  c_info "Source:  $src"
  c_info "Archive: $archive"
  hr

  # Creating an archive is non-destructive, but we still route it through run so
  # DRY_RUN=1 previews the exact command.
  run tar -cjvf "$archive" -- "$src"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "DRY_RUN=1: archive not actually created"
    return 0
  fi

  local size
  size="$(du -h "$archive" | cut -f1)"
  hr
  c_ok "Backup created: $archive (${size})"
}

do_extract() {
  local archive="$1"
  local target="$2"

  [[ -f "$archive" ]] || die "archive does not exist: $archive"

  need_cmd tar

  banner "Extract archive"
  c_info "Archive: $archive"
  c_info "Target:  $target"
  hr

  # Ensure the target directory exists (its creation is itself state-changing).
  if [[ ! -d "$target" ]]; then
    confirm "Target '$target' does not exist. Create it?" || die "aborted by user"
    run mkdir -p -- "$target"
  fi

  # Extraction overwrites files in the target, so confirm before mutating.
  confirm "Extract '$archive' into '$target'?" || { c_warn "Extraction cancelled"; return 0; }
  run tar -xjvf "$archive" -C "$target"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "DRY_RUN=1: nothing was extracted"
    return 0
  fi

  hr
  c_ok "Extracted $archive into $target"
}

main() {
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --extract)
      shift
      local archive="${1:-}"
      local target="${2:-}"
      [[ -n "$archive" && -n "$target" ]] || { usage; die "--extract requires ARCHIVE and TARGET_DIR"; }
      do_extract "$archive" "$target"
      ;;
    "")
      usage
      die "SRC argument is required"
      ;;
    *)
      local src="$1"
      local dest="${2:-.}"
      do_backup "$src" "$dest"
      ;;
  esac
}

main "$@"
