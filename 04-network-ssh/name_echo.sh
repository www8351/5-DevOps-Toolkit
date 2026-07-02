#!/usr/bin/env bash
#
# name_echo.sh — interactive name-echo demo
#   Prompts for a name and prints it three times per iteration.
#   Mirrors the original lab exercise from the walkthrough.
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

ITERATIONS="${1:-2}"

banner "Name echo demo"
printf '%s[?]%s Enter a name: ' "${_C_YEL:-}" "${_C_RESET:-}"
read -r name

for _ in $(seq 1 "$ITERATIONS"); do
  echo "$name $name $name"
done

c_ok "Done ($ITERATIONS iterations)"
