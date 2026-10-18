#!/usr/bin/env bash
#
# permfix.sh — recursively normalise directory/file modes and ownership (dry-run by default)
#   commands showcased: find, chmod, chown
#
# Usage: ./permfix.sh [options] <PATH>
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
permfix.sh — recursively normalise directory/file modes and ownership

Usage: $0 [options] <PATH>

Arguments:
  PATH            file tree to normalise (required, must exist)

Options:
  --dirs MODE    octal mode to apply to directories (default: 755)
  --files MODE   octal mode to apply to files (default: 644)
  -o OWNER[:GRP] also chown the tree to OWNER (optionally OWNER:GROUP)
  --execute      actually apply changes (DEFAULT IS DRY-RUN)
  -h, --help     show this help and exit

Notes:
  Dry-run by default: counts what would change and prints the commands.
  Pass --execute to apply. Refuses to run on / itself.
  Honours DRY_RUN=1 and ASSUME_YES=1. Changing owner to another user needs root.
EOF
}

main() {
  local target="" dmode="755" fmode="644" owner="" execute=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dirs) [[ -n "${2:-}" ]] || die "--dirs requires a MODE"; dmode="$2"; shift 2 ;;
      --files) [[ -n "${2:-}" ]] || die "--files requires a MODE"; fmode="$2"; shift 2 ;;
      -o) [[ -n "${2:-}" ]] || die "-o requires OWNER[:GROUP]"; owner="$2"; shift 2 ;;
      --execute) execute=1; shift ;;
      --) shift; break ;;
      -*) die "unknown option: $1" ;;
      *) target="$1"; shift ;;
    esac
  done
  # Trailing positional after --.
  [[ -z "$target" && $# -gt 0 ]] && target="$1"

  [[ -n "$target" ]] || { usage; die "missing required argument: PATH"; }
  [[ -e "$target" ]] || die "path does not exist: $target"
  # Octal only: find -perm needs it for the dry-run count, and a typo such as
  # 999 should fail here rather than halfway through the tree.
  [[ "$dmode" =~ ^[0-7]{3,4}$ ]] || die "--dirs MODE must be octal, e.g. 755 (got '$dmode')"
  [[ "$fmode" =~ ^[0-7]{3,4}$ ]] || die "--files MODE must be octal, e.g. 644 (got '$fmode')"
  if [[ -d "$target" && "$(cd "$target" && pwd -P)" == "/" ]]; then
    die "refusing to normalise modes across the whole filesystem (/)"
  fi

  need_cmd find
  need_cmd chmod
  [[ -n "$owner" ]] && need_cmd chown

  # Default to dry-run unless the caller explicitly opted in.
  if [[ "$execute" -eq 0 ]]; then
    export DRY_RUN=1
  fi

  banner "permfix: $target"
  c_info "dir mode  : $dmode"
  c_info "file mode : $fmode"
  [[ -n "$owner" ]] && c_info "owner     : $owner"
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_warn "DRY-RUN: no changes will be made (pass --execute to apply)"
    # Exact-mode match: entries already at the target mode are not counted.
    # Unreadable parts are skipped rather than aborting the preview.
    local nd nf
    nd="$({ find "$target" -type d ! -perm "$dmode" 2>/dev/null || true; } | wc -l)"
    nf="$({ find "$target" -type f ! -perm "$fmode" 2>/dev/null || true; } | wc -l)"
    c_info "would change: ${nd//[[:space:]]/} directory(ies), ${nf//[[:space:]]/} file(s)"
  fi

  # If we are really applying changes that touch ownership for someone else, need root.
  if [[ "${DRY_RUN:-0}" != "1" && -n "$owner" ]]; then
    local target_user="${owner%%:*}"
    if [[ "$target_user" != "$(id -un)" ]]; then
      require_root
    fi
  fi

  # Confirm only when we are actually going to mutate the filesystem.
  if [[ "${DRY_RUN:-0}" != "1" ]]; then
    confirm "Apply mode/ownership changes under '$target'?" || die "aborted by user"
  fi

  hr
  c_info "normalising directory modes -> $dmode"
  run find "$target" -type d -exec chmod "$dmode" {} +

  c_info "normalising file modes -> $fmode"
  run find "$target" -type f -exec chmod "$fmode" {} +

  if [[ -n "$owner" ]]; then
    c_info "setting ownership -> $owner"
    run chown -R "$owner" "$target"
  fi

  c_ok "done"
}

main "$@"
