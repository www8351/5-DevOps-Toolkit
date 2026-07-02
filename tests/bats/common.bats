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
  # CI runs as a non-root user, so require_root must reject.
  in_common 'require_root'
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs root"* ]]
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

# ── presentation & sourcing ───────────────────────────────────────────────────
@test "banner renders the title" {
  in_common 'banner Hi'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hi"* ]]
}

@test "hr prints a rule" {
  in_common 'hr'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "double-sourcing is a no-op guard" {
  run bash -c "source \"\$COMMON\"; source \"\$COMMON\"; c_ok twice"
  [ "$status" -eq 0 ]
  [ "$output" = "[✓] twice" ]
}
