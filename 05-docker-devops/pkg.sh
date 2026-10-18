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
  update           refresh the package index       (read-only)
  search TERM      search the repositories         (read-only)

Options:
  -h, --help       show this help and exit

Environment:
  DRY_RUN=1        print mutating commands instead of running them
  ASSUME_YES=1     skip the confirmation prompt

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

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -*)
        die "unknown option: $1 (try --help)"
        ;;
      *)
        break
        ;;
    esac
  done

  [[ $# -ge 1 ]] || { usage; die "missing subcommand"; }

  local sub="$1"
  shift

  local pm
  pm="$(detect_pm)"
  c_info "using package manager: $pm"

  case "$sub" in
    install)
      [[ $# -ge 1 ]] || die "install requires at least one package name"
      require_root
      confirm "Install with $pm: $* ?" || { c_warn "aborted"; exit 0; }
      run "$pm" install -y "$@"
      c_ok "install complete"
      ;;
    upgrade)
      [[ $# -eq 0 ]] || die "upgrade takes no arguments"
      require_root
      confirm "Upgrade all packages with $pm ?" || { c_warn "aborted"; exit 0; }
      case "$pm" in
        apt-get) run "$pm" upgrade -y ;;
        dnf|yum) run "$pm" upgrade -y ;;
      esac
      c_ok "upgrade complete"
      ;;
    remove)
      [[ $# -ge 1 ]] || die "remove requires at least one package name"
      require_root
      confirm "Remove with $pm: $* ?" || { c_warn "aborted"; exit 0; }
      run "$pm" remove -y "$@"
      c_ok "remove complete"
      ;;
    update)
      [[ $# -eq 0 ]] || die "update takes no arguments"
      case "$pm" in
        apt-get) run "$pm" update ;;
        dnf)     run "$pm" check-update || true ;;
        yum)     run "$pm" check-update || true ;;
      esac
      c_ok "index refreshed"
      ;;
    search)
      [[ $# -eq 1 ]] || die "search requires exactly one term"
      run "$pm" search "$1"
      ;;
    *)
      die "unknown subcommand: $sub (try --help)"
      ;;
  esac
}

main "$@"
