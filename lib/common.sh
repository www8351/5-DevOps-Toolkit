#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# lib/common.sh — shared engine for 5-DevOps-Toolkit
#
# Source it from any script (scripts live one level below repo root):
#     source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
#
# Public API:
#   c_info/c_ok/c_warn/c_err MSG   coloured log lines (warn/err -> stderr)
#   c_fail MSG                     red [✗] result line on stdout (a failed check)
#   die MSG                        log error + exit 1 (runtime failure)
#   usage_error MSG                log error + --help hint + exit 2 (bad usage)
#   need_arg OPT [VALUE]           usage_error unless OPT was given a value
#   help_requested ARGS...         true if -h/--help appears before `--`
#   deprecated OLD NEW             warn that a flag was renamed (D23)
#   need_cmd CMD                   abort if a dependency binary is missing
#   require_root                   abort unless EUID 0 (DRY_RUN=1 may preview)
#   confirm "question"             y/N prompt on stderr; honours ASSUME_YES=1
#   confirm_or_abort "question"    confirm, or exit 1 saying nothing changed
#   run CMD...                     exec, or just echo when DRY_RUN=1
#   json_str STRING                print STRING as a quoted JSON string
#   json_num VALUE                 print VALUE if it is a plain number, else null
#   hr                             terminal-wide horizontal rule
#   banner "TITLE"                 boxed section header
#
# Exit codes (D22): 0 success, 1 problem found / failure / declined, 2 usage.
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
c_fail() { printf '%s[✗]%s %s\n' "$_C_RED" "$_C_RESET" "$*"; }
die()    { c_err "$*"; exit 1; }

# ---- command-line conventions (D22) ------------------------------------------
# usage_error MSG — a bad flag, value or argument: exit 2, unlike die's 1, so a
# script can tell "you called me wrong" from "I found a problem".
usage_error() {
  c_err "$*"
  printf "    run '%s --help' for usage\n" "$(basename "$0")" >&2
  exit 2
}

# need_arg OPT [VALUE] — call as `need_arg "$@"` inside an option's case arm.
need_arg() { [[ $# -ge 2 ]] || usage_error "$1 needs a value"; }

# help_requested ARGS... — true if -h or --help appears before `--`, so help
# works wherever it is placed on the command line.
help_requested() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --) return 1 ;;
      -h|--help) return 0 ;;
    esac
  done
  return 1
}

# deprecated OLD NEW — the old flag still works, with this warning (D23).
deprecated() { c_warn "$1 is deprecated, use $2 instead (the old form goes away in 2.0.0)"; }

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
# The question goes to stderr so stdout carries only results.
confirm() {
  [[ "${ASSUME_YES:-0}" == "1" ]] && return 0
  local reply
  printf '%s[?]%s %s [y/N] ' "$_C_YEL" "$_C_RESET" "$*" >&2
  read -r reply || true
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

# confirm_or_abort "msg" — declining is exit 1 in every tool (D22).
confirm_or_abort() {
  confirm "$@" || { c_warn "aborted: nothing was changed"; exit 1; }
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

# ---- machine output ----------------------------------------------------------
# json_str STRING — print STRING as a JSON string literal (quotes included).
# Escapes backslash, quote and every control character; other bytes, UTF-8
# included, pass through unchanged.
json_str() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  if [[ "$s" == *[$'\001'-$'\037']* ]]; then
    local i ch out=""
    for ((i = 0; i < ${#s}; i++)); do
      ch="${s:i:1}"
      [[ "$ch" == [$'\001'-$'\037'] ]] && printf -v ch '\\u%04x' "'$ch"
      out+="$ch"
    done
    s="$out"
  fi
  printf '"%s"' "$s"
}

# json_num VALUE — print VALUE as a JSON number, or null when it is not a plain
# decimal number (empty, "?", "000" style placeholders are callers' business).
json_num() {
  if [[ "$1" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]; then printf '%s' "$1"; else printf 'null'; fi
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
