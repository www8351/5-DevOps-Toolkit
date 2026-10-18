#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# lib/common.sh — shared engine for 5-DevOps-Toolkit
#
# Source it from any script (scripts live one level below repo root):
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
#
# Public API:
#   c_info/c_ok/c_warn/c_err MSG   coloured log lines (warn/err -> stderr)
#   die MSG                        log error + exit 1
#   need_cmd CMD                   abort if a dependency binary is missing
#   require_root                   abort unless EUID 0 (DRY_RUN=1 may preview)
#   confirm "question"             y/N prompt; honours ASSUME_YES=1
#   run CMD...                     exec, or just echo when DRY_RUN=1
#   hr                             terminal-wide horizontal rule
#   banner "TITLE"                 boxed section header
#
# Environment toggles:
#   NO_COLOR=1   disable ANSI colour
#   DRY_RUN=1    `run` prints instead of executing
#   ASSUME_YES=1 `confirm` auto-answers yes (use in CI only)
# ──────────────────────────────────────────────────────────────────────────────

# Guard against double-sourcing.
[[ -n "${_DEVOPS_TOOLKIT_COMMON:-}" ]] && return 0
_DEVOPS_TOOLKIT_COMMON=1

# ---- colour palette (auto-off when not a TTY or NO_COLOR set) ----------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\033[0m'; _C_RED=$'\033[31m';  _C_GRN=$'\033[32m'
  _C_YEL=$'\033[33m';  _C_BLU=$'\033[34m';  _C_BOLD=$'\033[1m'
else
  _C_RESET=''; _C_RED=''; _C_GRN=''; _C_YEL=''; _C_BLU=''; _C_BOLD=''
fi

# ---- logging -----------------------------------------------------------------
c_info() { printf '%s[i]%s %s\n' "$_C_BLU" "$_C_RESET" "$*"; }
c_ok()   { printf '%s[✓]%s %s\n' "$_C_GRN" "$_C_RESET" "$*"; }
c_warn() { printf '%s[!]%s %s\n' "$_C_YEL" "$_C_RESET" "$*" >&2; }
c_err()  { printf '%s[✗]%s %s\n' "$_C_RED" "$_C_RESET" "$*" >&2; }
die()    { c_err "$*"; exit 1; }

# ---- guards ------------------------------------------------------------------
# need_cmd CMD — fail fast if a required binary is not on PATH.
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"; }

# require_root — refuse to continue unless running as root. Under DRY_RUN=1 a
# normal user may continue: every side effect goes through `run`, which only
# prints, so the preview cannot change the system.
require_root() {
  [[ "$(id -u)" -eq 0 ]] && return 0
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    c_warn "not root: DRY_RUN=1 preview only, nothing will be changed"
    return 0
  fi
  die "this action needs root; re-run with sudo (preview first with: sudo DRY_RUN=1 $0 ...)"
}

# confirm "msg" — interactive y/N. Returns 0 on yes. ASSUME_YES=1 bypasses.
confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  local reply
  printf '%s[?]%s %s [y/N] ' "$_C_YEL" "$_C_RESET" "$*"
  read -r reply || true
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# ---- execution wrapper -------------------------------------------------------
# run CMD... — echo the command when DRY_RUN=1, otherwise execute it.
run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$_C_YEL" "$_C_RESET" "$*"
  else
    "$@"
  fi
}

# ---- presentation ------------------------------------------------------------
# _rule N — print N '─' characters. Built with parameter expansion, not `tr`:
# tr swaps single bytes, and '─' is three bytes in UTF-8.
_rule() { local s; printf -v s '%*s' "$1" ''; printf '%s' "${s// /─}"; }

hr() { _rule "${COLUMNS:-60}"; printf '\n'; }

banner() {
  local title="  $*  " line
  line="$(_rule "${#title}")"
  printf '%s┌%s┐%s\n' "$_C_BOLD" "$line" "$_C_RESET"
  printf '%s│%s│%s\n' "$_C_BOLD" "$title" "$_C_RESET"
  printf '%s└%s┘%s\n' "$_C_BOLD" "$line" "$_C_RESET"
}
