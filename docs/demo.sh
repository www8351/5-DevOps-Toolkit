#!/usr/bin/env bash
#
# demo.sh — run a short, safe tour of the read-only tools (perfect for a
#   recording). Every step is read-only: no root, no writes, no network changes.
#   Steps that need a missing dependency are skipped, not fatal, so the tour
#   always completes.
#
# Usage: ./docs/demo.sh [-h]
#
set -uo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
demo.sh — a safe, read-only tour of 5-DevOps-Toolkit for demos/recordings

Usage: $0 [-h]

Runs a handful of read-only tools (system info, directory sizes, HTTP health,
network info, top processes). No root, no writes, no config changes. Missing
dependencies are skipped rather than aborting the tour.

Record it with:  asciinema rec docs/demo.cast -c "bash docs/demo.sh"
EOF
}

# step "Title" cmd args... — banner + run; tolerate failure so the tour continues.
step() {
  local title="$1"; shift
  banner "$title"
  if "$@"; then
    :
  else
    c_warn "step skipped (missing dependency or unsupported platform)"
  fi
  hr
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") : ;;
    *) die "unexpected argument: $1 (try -h)" ;;
  esac

  banner "5-DevOps-Toolkit — read-only demo"
  c_info "every step below is safe: no root, no writes, no network changes"
  hr

  step "System dashboard"      "$ROOT/03-system-monitor/sysinfo.sh"
  step "Largest subdirectories" "$ROOT/01-file-text-toolkit/dirsnap.sh" -n 5 "$ROOT"
  step "Text stats (README)"    "$ROOT/01-file-text-toolkit/txtstats.sh" "$ROOT/README.md"
  step "Network interfaces"     "$ROOT/04-network-ssh/netinfo.sh"
  step "HTTP endpoint health"   "$ROOT/04-network-ssh/httpcheck.sh" https://example.com
  step "Top processes by CPU"   "$ROOT/03-system-monitor/topproc.sh" -n 5

  c_ok "demo complete — every tool above is read-only and re-runnable"
}

main "$@"
