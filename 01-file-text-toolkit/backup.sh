#!/usr/bin/env bash
#
# backup.sh — timestamped tar.bz2 backup of a directory, plus an extract mode
#   commands showcased: tar -cjvf, tar -xjvf -C, du, date
#
# Usage: ./backup.sh [--dry-run] [--yes] SRC [DEST_DIR] | --extract ARCHIVE TARGET_DIR
#        ./backup.sh --extract ARCHIVE TARGET_DIR
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
backup.sh — timestamped tar.bz2 backup of a directory, plus an extract mode

Usage:
  $0 [options] SRC [DEST_DIR]               create DEST_DIR/<basename>-<timestamp>.tar.bz2
  $0 [options] --extract ARCHIVE TARGET_DIR extract ARCHIVE into TARGET_DIR

Options:
  --extract      extract ARCHIVE into TARGET_DIR instead of creating a backup
  --dry-run      print the tar command instead of running it (same as DRY_RUN=1)
  --yes          skip the confirmation prompts (same as ASSUME_YES=1)
  -h, --help     show this help and exit

Backup mode is non-destructive. Extract mode asks for confirmation first.

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
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
    confirm_or_abort "Target '$target' does not exist. Create it?"
    run mkdir -p -- "$target"
  fi

  # Extraction overwrites files in the target, so confirm before mutating.
  confirm_or_abort "Extract '$archive' into '$target'?"
  run tar -xjvf "$archive" -C "$target"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "DRY_RUN=1: nothing was extracted"
    return 0
  fi

  hr
  c_ok "Extracted $archive into $target"
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local extract=0
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --extract) extract=1; shift ;;
      --dry-run) export DRY_RUN=1; shift ;;
      --yes)     export ASSUME_YES=1; shift ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  if [[ "$extract" -eq 1 ]]; then
    [[ "${#args[@]}" -eq 2 ]] || usage_error "--extract needs ARCHIVE and TARGET_DIR"
    do_extract "${args[0]}" "${args[1]}"
  else
    [[ "${#args[@]}" -ge 1 && "${#args[@]}" -le 2 ]] || usage_error "expected SRC [DEST_DIR]"
    do_backup "${args[0]}" "${args[1]:-.}"
  fi
}

main "$@"
