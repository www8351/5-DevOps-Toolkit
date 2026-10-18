#!/usr/bin/env bats
#
# Contract smoke test: every tool script must answer -h and --help with exit 0
# and print its own name in the usage text — WITHOUT requiring its runtime
# dependencies (help must work before any need_cmd guard).
#
# Excluded: setup.sh, the venv bootstrapper, which forwards every argument
# (help included) to the Python package after building the venv.

load helper

@test "every tool script supports -h and --help (exit 0, usage names the script)" {
  local failures=()
  local script base flag
  while IFS= read -r script; do
    base="$(basename "$script")"
    case "$base" in
      setup.sh) continue ;;
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

# The tool scripts the CLI contract applies to (helpers excluded, as above).
tool_scripts() {
  find "$REPO_ROOT" -name '*.sh' -not -path '*/lib/*' -not -path '*/.git/*' \
    -not -path '*/.venv/*' -not -name setup.sh | sort
}

@test "every tool rejects an unknown option with exit 2 (D22)" {
  local failures=() script
  while IFS= read -r script; do
    run bash "$script" --definitely-not-an-option </dev/null
    [ "$status" -eq 2 ] || failures+=("$(basename "$script"): exit $status (expected 2)")
  done < <(tool_scripts)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'usage-error contract violations:\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}

@test "every tool shows help when --help comes after another argument (D22)" {
  local failures=() script base
  while IFS= read -r script; do
    base="$(basename "$script")"
    run bash "$script" some-argument --help </dev/null
    if [ "$status" -ne 0 ] || [[ "$output" != *"$base"* ]]; then
      failures+=("$base: exit $status")
    fi
  done < <(tool_scripts)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'help-anywhere contract violations:\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}

@test "every tool treats -- as the end of options, never as an unknown option (D22)" {
  # `-- --x` makes "--x" a plain argument. Every tool must then either reject
  # it as an unexpected argument or use it as a value; none may call -- unknown.
  # DRY_RUN, a temp HOME and a closed stdin keep the odd tool that does run
  # harmless.
  local failures=() script
  while IFS= read -r script; do
    DRY_RUN=1 HOME="$BATS_TEST_TMPDIR" run bash "$script" -- --x </dev/null
    ! grep -qx '.*unknown option: --' <<<"$output" || failures+=("$(basename "$script")")
  done < <(tool_scripts)

  if [ "${#failures[@]}" -ne 0 ]; then
    printf 'tools that reject --:\n'
    printf '  - %s\n' "${failures[@]}"
    return 1
  fi
}
