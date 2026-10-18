#!/usr/bin/env bash
#
# sysinfo.sh — boxed dashboard of host, kernel, CPU, memory and disk
#   commands showcased: uname, hostnamectl, lscpu, df, free, uptime
#
# Usage: ./sysinfo.sh
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
sysinfo.sh — boxed dashboard of host, kernel, CPU, memory and disk

Usage: $0 [options]

Prints a one-glance, read-only dashboard with the following sections:
  Host        hostnamectl (or hostname + uname -n fallback)
  Kernel/OS   uname -a
  CPU         lscpu summary (model, core count, architecture)
  Memory      free -h
  Disk        df -h (real filesystems only)
  Uptime      uptime / load average

Optional tools that are absent are reported and skipped, never fatal.

Options:
  -h, --help     show this help and exit
EOF
}

# have CMD — true if an optional command is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

section_host() {
  banner "Host"
  if have hostnamectl; then
    hostnamectl
  else
    c_warn "hostnamectl not found — using hostname + uname -n"
    printf '   Hostname: %s\n' "$(hostname 2>/dev/null || uname -n)"
    printf 'Static name: %s\n' "$(uname -n)"
  fi
  echo
}

section_kernel() {
  banner "Kernel / OS"
  if have uname; then
    uname -a
  else
    c_warn "uname not found — skipping kernel section"
  fi
  echo
}

section_cpu() {
  banner "CPU"
  if have lscpu; then
    # Pull just the headline rows; '|| true' keeps a no-match grep from
    # tripping pipefail on exotic locales.
    lscpu | grep -E '^(Architecture|CPU\(s\)|Model name|Vendor ID|Thread\(s\) per core|Core\(s\) per socket):' || true
  else
    c_warn "lscpu not found — skipping CPU section"
  fi
  echo
}

section_memory() {
  banner "Memory"
  if have free; then
    free -h
  else
    c_warn "free not found — skipping memory section"
  fi
  echo
}

section_disk() {
  banner "Disk"
  if have df; then
    # Drop pseudo/virtual filesystems so the table shows real storage only.
    df -h | grep -vE '^(tmpfs|overlay|devtmpfs|udev|none)' || true
  else
    c_warn "df not found — skipping disk section"
  fi
  echo
}

section_uptime() {
  banner "Uptime / Load"
  if have uptime; then
    uptime
  else
    c_warn "uptime not found — skipping uptime section"
  fi
  echo
}

main() {
  case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") : ;;
    *) die "unexpected argument: $1 (try -h)" ;;
  esac

  section_host
  section_kernel
  section_cpu
  section_memory
  section_disk
  section_uptime
}

main "$@"
