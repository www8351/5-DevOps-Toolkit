#!/usr/bin/env bats
#
# Contract smoke test: every tool script must answer -h and --help with exit 0
# and print its own name in the usage text — WITHOUT requiring its runtime
# dependencies (help must work before any need_cmd guard).
#
# Helpers excluded: name_echo.sh (interactive demo) and setup.sh (venv
# bootstrapper) are not "tools" and intentionally have no -h.

load helper

@test "every tool script supports -h and --help (exit 0, usage names the script)" {
  local failures=()
  local script base flag
  while IFS= read -r script; do
    base="$(basename "$script")"
    case "$base" in
      name_echo.sh|setup.sh) continue ;;
    esac

    for flag in -h --help; do
      run bash "$script" "$flag" </dev/null
      if [ "$status" -ne 0 ]; then
        failures+=("$base $flag: exit $status (expected 0)")
        continue
      fi
      if [[ "$output" != *"$base"* ]]; then
        failures+=("$base $flag: usage text does not mention the script name")
      fi
    done
  done < <(find "$REPO_ROOT" -name '*.sh' -not -path '*/lib/*' -not -path '*/.git/*' \
             -not -path '*/.venv/*' | sort)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'help contract violations:\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}

@test "every entry point is executable after a fresh clone" {
  # lib/common.sh is sourced, never executed, so it is not listed here.
  local failures=()
  local script
  while IFS= read -r script; do
    [ -x "$script" ] || failures+=("${script#"$REPO_ROOT"/}")
  done < <(find "$REPO_ROOT" \( -name '*.sh' -o -name 'ec2-deploy.py' \) \
             -not -path '*/lib/*' -not -path '*/.git/*' -not -path '*/.venv/*' | sort)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'not executable (fix with: git update-index --chmod=+x FILE):\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}
