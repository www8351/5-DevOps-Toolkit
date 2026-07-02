#!/usr/bin/env bats
#
# Contract smoke test: every tool script must answer -h with exit 0 and print
# its own name in the usage text — WITHOUT requiring its runtime dependencies
# (help must work before any need_cmd guard).
#
# Helpers excluded: name_echo.sh (interactive demo) and setup.sh (venv
# bootstrapper) are not "tools" and intentionally have no -h.

load helper

@test "every tool script supports -h (exit 0, usage names the script)" {
  local failures=()
  local script base
  while IFS= read -r script; do
    base="$(basename "$script")"
    case "$base" in
      name_echo.sh|setup.sh) continue ;;
    esac

    run bash "$script" -h </dev/null
    if [ "$status" -ne 0 ]; then
      failures+=("$base: exit $status (expected 0)")
      continue
    fi
    if [[ "$output" != *"$base"* ]]; then
      failures+=("$base: usage text does not mention the script name")
    fi
  done < <(find "$REPO_ROOT" -name '*.sh' -not -path '*/lib/*' -not -path '*/.git/*' | sort)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'help contract violations:\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}
