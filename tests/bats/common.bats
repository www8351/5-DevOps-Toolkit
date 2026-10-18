#!/usr/bin/env bats
#
# Unit tests for lib/common.sh — the shared engine every tool sources.
# Helpers are exercised in a child bash (see helper.bash for why).

load helper

# Convenience: run a snippet with common.sh already sourced.
in_common() {
  run bash -c "source \"\$COMMON\"; $1"
}

# ── logging ───────────────────────────────────────────────────────────────────
@test "c_info prints [i] tag to stdout" {
  in_common 'c_info hello'
  [ "$status" -eq 0 ]
  [ "$output" = "[i] hello" ]
}

@test "c_ok prints [✓] tag" {
  in_common 'c_ok hello'
  [ "$status" -eq 0 ]
  [ "$output" = "[✓] hello" ]
}

@test "c_warn emits [!] (to stderr)" {
  in_common 'c_warn careful'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[!]"* ]]
  [[ "$output" == *"careful"* ]]
}

@test "c_err emits [✗] (to stderr)" {
  in_common 'c_err broke'
  [ "$status" -eq 0 ]
  [[ "$output" == *"[✗]"* ]]
  [[ "$output" == *"broke"* ]]
}

@test "c_err writes to stderr, not stdout" {
  # Drop the child's stdout; if c_err wrongly used stdout, $output would be empty.
  run bash -c "source \"\$COMMON\"; c_err oops 1>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"oops"* ]]
}

@test "c_warn writes to stderr, not stdout" {
  run bash -c "source \"\$COMMON\"; c_warn careful 1>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"careful"* ]]
}

@test "die logs error and exits 1" {
  in_common 'die boom'
  [ "$status" -eq 1 ]
  [[ "$output" == *"[✗]"* ]]
  [[ "$output" == *"boom"* ]]
}

# ── guards ────────────────────────────────────────────────────────────────────
@test "need_cmd succeeds for an existing binary" {
  in_common 'need_cmd bash'
  [ "$status" -eq 0 ]
}

@test "need_cmd fails for a missing binary" {
  in_common 'need_cmd __definitely_missing_binary_xyz__'
  [ "$status" -eq 1 ]
  [[ "$output" == *"required command not found"* ]]
}

@test "require_root refuses a non-root user" {
  # Stub id so the result does not depend on the runner's real uid.
  in_common 'id() { echo 1000; }; require_root'
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs root"* ]]
}

@test "require_root passes for root" {
  in_common 'id() { echo 0; }; require_root && echo continued'
  [ "$status" -eq 0 ]
  [ "$output" = "continued" ]
}

@test "require_root lets a non-root user preview under DRY_RUN=1" {
  run bash -c "source \"\$COMMON\"; id() { echo 1000; }; DRY_RUN=1 require_root && echo continued"
  [ "$status" -eq 0 ]
  [[ "$output" == *"preview only"* ]]
  [[ "$output" == *"continued"* ]]
}

# ── run (DRY_RUN) ─────────────────────────────────────────────────────────────
@test "run executes the command normally" {
  in_common 'run echo hi'
  [ "$status" -eq 0 ]
  [ "$output" = "hi" ]
}

@test "run only prints the command under DRY_RUN=1" {
  run bash -c "source \"\$COMMON\"; DRY_RUN=1 run echo hi"
  [ "$status" -eq 0 ]
  [ "$output" = "[dry-run] echo hi" ]
}

@test "run propagates the wrapped command's exit code" {
  in_common 'run false'
  [ "$status" -eq 1 ]
}

# ── confirm ───────────────────────────────────────────────────────────────────
@test "confirm auto-yeses under ASSUME_YES=1 without prompting" {
  run bash -c "source \"\$COMMON\"; ASSUME_YES=1 confirm 'go?'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "confirm returns 0 on y" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< "y"
  [ "$status" -eq 0 ]
}

@test "confirm returns 0 on yes" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< "yes"
  [ "$status" -eq 0 ]
}

@test "confirm returns non-zero on n" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< "n"
  [ "$status" -ne 0 ]
}

@test "confirm returns non-zero on empty answer" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< ""
  [ "$status" -ne 0 ]
}

@test "confirm accepts uppercase YES (case-insensitive)" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< "YES"
  [ "$status" -eq 0 ]
}

@test "confirm rejects non-anchored input like 'yeah'" {
  run bash -c "source \"\$COMMON\"; confirm 'go?'" <<< "yeah"
  [ "$status" -ne 0 ]
}

# ── CLI conventions (D22) ─────────────────────────────────────────────────────
@test "usage_error explains, points at --help and exits 2" {
  in_common 'usage_error "unknown option: --bogus"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown option: --bogus"* ]]
  [[ "$output" == *"--help"* ]]
}

@test "usage_error writes to stderr" {
  run bash -c "source \"\$COMMON\"; usage_error oops 1>/dev/null"
  [ "$status" -eq 2 ]
  [[ "$output" == *"oops"* ]]
}

@test "need_arg passes when the option has a value" {
  in_common 'need_arg --top 5 && echo ok'
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
}

@test "need_arg is a usage error when the value is empty" {
  in_common 'need_arg --owner ""'
  [ "$status" -eq 2 ]
  [[ "$output" == *"--owner needs a value"* ]]
}

@test "need_arg is a usage error when the value is missing" {
  in_common 'need_arg --top'
  [ "$status" -eq 2 ]
  [[ "$output" == *"--top needs a value"* ]]
}

@test "help_requested finds -h or --help anywhere" {
  in_common 'help_requested -n 3 --help && help_requested file -h && echo yes'
  [ "$output" = "yes" ]
}

@test "help_requested ignores everything after --" {
  in_common 'help_requested -n 3 -- --help || echo no'
  [ "$output" = "no" ]
}

@test "help_requested is false without a help flag" {
  in_common 'help_requested -n 3 file || echo no'
  [ "$output" = "no" ]
}

@test "deprecated warns on stderr, names the new flag and the removal" {
  run bash -c "source \"\$COMMON\"; deprecated -f --field 1>/dev/null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-f is deprecated"* ]]
  [[ "$output" == *"--field"* ]]
  [[ "$output" == *"2.0.0"* ]]
}

@test "confirm asks on stderr, so stdout stays clean for results" {
  run bash -c "source \"\$COMMON\"; confirm 'go?' 2>/dev/null" <<< "y"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "confirm_or_abort exits 1 and says nothing was changed" {
  run bash -c "source \"\$COMMON\"; confirm_or_abort 'go?'; echo after" <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing was changed"* ]]
  [[ "$output" != *"after"* ]]
}

@test "confirm_or_abort continues on yes" {
  run bash -c "source \"\$COMMON\"; confirm_or_abort 'go?'; echo after" <<< "y"
  [ "$status" -eq 0 ]
  [[ "$output" == *"after"* ]]
}

@test "c_fail prints a [✗] result line to stdout" {
  run bash -c "source \"\$COMMON\"; c_fail down 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$output" = "[✗] down" ]
}

@test "json_str output round-trips through a JSON parser" {
  local input=$'quote" back\\slash tab\t nl\n bell\a unicode ✓ end'
  run bash -c 'source "$COMMON"; json_str "$1"' _ "$input"
  [ "$status" -eq 0 ]
  run python3 -c 'import json, sys; print(json.loads(sys.argv[1]) == sys.argv[2])' "$output" "$input"
  [ "$output" = "True" ]
}

@test "json_num passes numbers through and turns anything else into null" {
  in_common 'json_num 42; echo; json_num 1.25; echo; json_num -3; echo; json_num 0.5; echo; json_num ""; echo; json_num 1e3; echo; json_num 12abc; echo; json_num 007'
  [ "$output" = $'42\n1.25\n-3\n0.5\nnull\nnull\nnull\nnull' ]
}

# ── presentation & sourcing ───────────────────────────────────────────────────
@test "banner draws a closed box around the title" {
  in_common 'banner Hi'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "┌──────┐" ]
  [ "${lines[1]}" = "│  Hi  │" ]
  [ "${lines[2]}" = "└──────┘" ]
}

@test "hr draws COLUMNS box-drawing characters" {
  # Exact match: a byte-wise rule (tr) would print broken UTF-8 instead.
  run bash -c "source \"\$COMMON\"; COLUMNS=5 hr"
  [ "$status" -eq 0 ]
  [ "$output" = "─────" ]
}

@test "double-sourcing is a no-op guard" {
  run bash -c "source \"\$COMMON\"; source \"\$COMMON\"; c_ok twice"
  [ "$status" -eq 0 ]
  [ "$output" = "[✓] twice" ]
}
