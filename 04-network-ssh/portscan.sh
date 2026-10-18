#!/usr/bin/env bash
#
# portscan.sh — discover live hosts on a subnet and scan open ports
#   commands showcased: nmap -sn, nmap -Pn -sV
#
# Usage: ./portscan.sh [options] <target>
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
portscan.sh — discover live hosts on a subnet and scan open ports

Usage: $0 [options] <target>

Arguments:
  target         host or CIDR to scan (e.g. 192.168.1.10 or 192.168.1.0/24)

Options:
  -p PORTS       ports to scan, e.g. 22,80,443 or 1-1000 (default: nmap default set)
  --discover     host discovery only (nmap -sn), no port scan
  -h, --help     show this help and exit

!! AUTHORIZATION WARNING !!
  Port scanning systems you do not own or lack explicit written permission to
  test may be illegal and is against the acceptable-use policy of most networks.
  ONLY scan hosts you own or are explicitly permitted to test. You alone are
  responsible for how you use this tool.

Read-only: this script does not modify the local system.
EOF
}

main() {
  local ports=""
  local discover=0
  local target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --discover) discover=1; shift ;;
      -p)
        [[ $# -ge 2 ]] || die "-p requires a PORTS argument"
        ports="$2"
        shift 2
        ;;
      -*) die "unknown option: $1 (try -h)" ;;
      *)
        [[ -z "$target" ]] || die "only one target allowed (got extra: $1)"
        target="$1"
        shift
        ;;
    esac
  done

  [[ -n "$target" ]] || die "target is required (host or CIDR; try -h)"

  # Dependency guard after arg parsing so -h/usage work without nmap installed.
  need_cmd nmap

  # Reiterate the warning at run time so it is impossible to miss.
  c_warn "AUTHORIZATION: only scan hosts you own or are permitted to test."

  if [[ "$discover" -eq 1 ]]; then
    banner "Host discovery: $target"
    nmap -sn "$target"
    return
  fi

  banner "Port scan: $target"
  if [[ -n "$ports" ]]; then
    c_info "scanning ports: $ports"
    nmap -Pn -sV -p "$ports" "$target"
  else
    c_info "scanning nmap default port set"
    nmap -Pn -sV "$target"
  fi
}

main "$@"
