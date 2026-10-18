#!/usr/bin/env bash
#
# netinfo.sh — show interfaces, routes, default gateway and listening ports
#   commands showcased: ip addr, ip route, ss -tlnp, netstat
#
# Usage: ./netinfo.sh
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
netinfo.sh — show interfaces, routes, default gateway and listening ports

Usage: $0

Options:
  -h, --help     show this help and exit

Read-only: inspects local networking state, changes nothing.
EOF
}

show_addresses() {
  banner "Addresses"
  if command -v ip >/dev/null 2>&1; then
    if ip -brief addr >/dev/null 2>&1; then
      ip -brief addr
    else
      ip addr
    fi
  elif command -v ifconfig >/dev/null 2>&1; then
    c_warn "ip not found; falling back to ifconfig"
    ifconfig -a
  else
    c_warn "neither ip nor ifconfig found; skipping addresses"
  fi
}

show_routes() {
  banner "Routes"
  if command -v ip >/dev/null 2>&1; then
    ip route
  elif command -v route >/dev/null 2>&1; then
    c_warn "ip not found; falling back to route -n"
    route -n
  else
    c_warn "neither ip nor route found; skipping routes"
  fi
}

show_gateway() {
  banner "Default gateway"
  local gw=""
  if command -v ip >/dev/null 2>&1; then
    gw="$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')"
  elif command -v route >/dev/null 2>&1; then
    gw="$(route -n 2>/dev/null | awk '$1 == "0.0.0.0" {print $2; exit}')"
  fi
  if [[ -n "$gw" ]]; then
    c_ok "default gateway: $gw"
  else
    c_warn "no default gateway found"
  fi
}

show_listening() {
  banner "Listening ports"
  if command -v ss >/dev/null 2>&1; then
    ss -tlnp
  elif command -v netstat >/dev/null 2>&1; then
    c_warn "ss not found; falling back to netstat -tlnp"
    netstat -tlnp
  else
    c_warn "neither ss nor netstat found; skipping listening ports"
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      *) die "unknown argument: $1 (try -h)" ;;
    esac
  done

  show_addresses
  hr
  show_routes
  hr
  show_gateway
  hr
  show_listening
}

main "$@"
