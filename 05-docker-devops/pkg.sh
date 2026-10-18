#!/usr/bin/env bash
#
# pkg.sh — distro-agnostic package manager wrapper (apt/dnf/yum)
#   commands showcased: apt-get, dnf, yum
#
# Usage: ./pkg.sh [options] <subcommand> [args...]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
pkg.sh — distro-agnostic package manager wrapper (apt/dnf/yum)

Usage: $0 [options] <subcommand> [args...]

Subcommands:
  install PKG...   install one or more packages   (root + confirm)
  upgrade          upgrade all installed packages  (root + confirm)
  remove PKG...    remove one or more packages     (root + confirm)
  update           refresh the package index       (root with apt-get)
  search TERM      search the repositories         (read-only)

Options (accepted before or after the subcommand):
  --dry-run        print mutating commands instead of running them (DRY_RUN=1)
  --yes            skip the confirmation prompt (ASSUME_YES=1)
  -h, --help       show this help and exit

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.

The package manager is auto-detected in this order: apt-get, dnf, yum.
EOF
}

# Detect the available package manager; echo its name or die.
detect_pm() {
  local pm
  for pm in apt-get dnf yum; do
    if command -v "$pm" >/dev/null 2>&1; then
      printf '%s\n' "$pm"
      return 0
    fi
  done
  die "no supported package manager found (need apt-get, dnf or yum)"
}

# done_ok MSG — report success, unless this was only a DRY_RUN preview.
done_ok() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_info "dry run finished: nothing was changed"
  else
    c_ok "$1"
  fi
}

main() {
  help_requested "$@" && { usage; exit 0; }

  # Flags may sit anywhere; package names never start with '-'.
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) export DRY_RUN=1; shift ;;
      --yes)     export ASSUME_YES=1; shift ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done

  [[ "${#args[@]}" -ge 1 ]] || usage_error "missing subcommand"
  set -- "${args[@]}"

  local sub="$1"
  shift
  case "$sub" in
    install|upgrade|remove|update|search) ;;
    *) usage_error "unknown subcommand: $sub" ;;
  esac

  local pm
  pm="$(detect_pm)"
  c_info "using package manager: $pm"

  case "$sub" in
    install)
      [[ $# -ge 1 ]] || usage_error "install requires at least one package name"
      require_root
      confirm_or_abort "Install with $pm: $*?"
      run "$pm" install -y "$@"
      done_ok "install complete"
      ;;
    upgrade)
      [[ $# -eq 0 ]] || usage_error "upgrade takes no arguments"
      require_root
      confirm_or_abort "Upgrade all packages with $pm?"
      case "$pm" in
        apt-get) run "$pm" upgrade -y ;;
        dnf|yum) run "$pm" upgrade -y ;;
      esac
      done_ok "upgrade complete"
      ;;
    remove)
      [[ $# -ge 1 ]] || usage_error "remove requires at least one package name"
      require_root
      confirm_or_abort "Remove with $pm: $*?"
      run "$pm" remove -y "$@"
      done_ok "remove complete"
      ;;
    update)
      [[ $# -eq 0 ]] || usage_error "update takes no arguments"
      case "$pm" in
        apt-get) require_root; run "$pm" update ;;
        dnf|yum)
          # check-update exits 100 when updates are available; only other
          # non-zero codes are real failures.
          local rc=0
          run "$pm" check-update || rc=$?
          [[ "$rc" -eq 0 || "$rc" -eq 100 ]] || die "$pm check-update failed (exit $rc)"
          ;;
      esac
      done_ok "index refreshed"
      ;;
    search)
      [[ $# -eq 1 ]] || usage_error "search requires exactly one term"
      # A query, not a change to installed packages, so it bypasses `run` and
      # still answers under DRY_RUN=1 (dnf/yum may refresh their metadata cache).
      # apt-get has no search command; apt-cache does.
      case "$pm" in
        apt-get) need_cmd apt-cache; apt-cache search "$1" ;;
        dnf|yum) "$pm" search "$1" ;;
      esac
      ;;
  esac
}

main "$@"
