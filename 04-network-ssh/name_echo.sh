#!/usr/bin/env bash
#
# name_echo.sh — interactive name-echo demo
#   Prompts for a name and prints it three times per iteration.
#   Mirrors the original lab exercise from the walkthrough.
#
# Usage: ./name_echo.sh [ITERATIONS]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
name_echo.sh — interactive name-echo demo

Usage: $0 [ITERATIONS]

Asks for a name, then prints it three times on each of ITERATIONS lines
(default: 2).

Options:
  -h, --help     show this help and exit

Exit status: 0 on success, 2 on a usage error.
EOF
}

main() {
  help_requested "$@" && { usage; exit 0; }

  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;
      *) args+=("$1"); shift ;;
    esac
  done
  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one ITERATIONS value"
  local iterations="${args[0]:-2}"
  [[ "$iterations" =~ ^[1-9][0-9]*$ ]] || usage_error "ITERATIONS must be a positive integer (got '$iterations')"

  banner "Name echo demo"
  printf '%s[?]%s Enter a name: ' "$_C_YEL" "$_C_RESET" >&2
  local name=""
  read -r name || true

  local i
  for ((i = 0; i < iterations; i++)); do
    echo "$name $name $name"
  done

  c_ok "Done ($iterations iterations)"
}

main "$@"
