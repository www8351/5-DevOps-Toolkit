#!/usr/bin/env bash
#
# sshkey.sh — generate an ed25519 SSH keypair and optionally copy it to a host
#   commands showcased: ssh-keygen -t ed25519, ssh-copy-id
#
# Usage: ./sshkey.sh [options]
#
set -euo pipefail

# shellcheck source=../lib/common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"

usage() {
  cat <<EOF
sshkey.sh — generate an ed25519 SSH keypair and optionally copy it to a host

Usage: $0 [options]

Options:
  -f, --file KEYFILE   private key path (default: ~/.ssh/id_ed25519)
  -C, --comment TEXT   key comment (default: user@host)
  --copy-to USER@HOST  copy the public key to USER@HOST afterwards (ssh-copy-id)
  --dry-run            print the commands instead of running them (DRY_RUN=1)
  --yes                skip the prompts (ASSUME_YES=1), including the one before
                       replacing an existing key
  -h, --help           show this help and exit

Deprecated (still works, removed in 2.0.0): -c USER@HOST (use --copy-to).

Exit status: 0 on success, 1 on a failure or a declined prompt, 2 on a usage
error.
EOF
}

main() {
  local keyfile="${HOME}/.ssh/id_ed25519"
  local comment=""
  local copy_target=""

  help_requested "$@" && { usage; exit 0; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -f|--file)    need_arg "$@"; keyfile="$2"; shift 2 ;;
      -C|--comment) need_arg "$@"; comment="$2"; shift 2 ;;
      --copy-to)    need_arg "$@"; copy_target="$2"; shift 2 ;;
      -c)           deprecated -c --copy-to; need_arg "$@"; copy_target="$2"; shift 2 ;;
      --dry-run)    export DRY_RUN=1; shift ;;
      --yes)        export ASSUME_YES=1; shift ;;
      --) shift; [[ $# -eq 0 ]] || usage_error "unexpected argument: $1"; break ;;
      -*) usage_error "unknown option: $1" ;;
      *)  usage_error "unexpected argument: $1" ;;
    esac
  done

  # Dependency guard after arg parsing so -h/usage work without ssh-keygen installed.
  need_cmd ssh-keygen

  if [[ -z "$comment" ]]; then
    local user host
    user="${USER:-$(id -un)}"
    host="$(hostname 2>/dev/null || echo localhost)"
    comment="${user}@${host}"
  fi

  banner "Generate ed25519 key"
  c_info "key file: $keyfile"
  c_info "comment : $comment"

  if [[ -e "$keyfile" ]]; then
    c_warn "key already exists: $keyfile"
    confirm_or_abort "Overwrite existing key $keyfile?"
  fi

  # Ensure the parent directory exists with sane permissions.
  local keydir
  keydir="$(dirname "$keyfile")"
  if [[ ! -d "$keydir" ]]; then
    run mkdir -p "$keydir"
    run chmod 700 "$keydir"
  fi

  if [[ -e "$keyfile" ]]; then
    # Generate beside the old pair and swap it in only once ssh-keygen has
    # succeeded: the old key survives a failure, and ssh-keygen never stops
    # at its own "Overwrite (y/n)?" prompt, which would hang a --yes run.
    local tmpkey="${keyfile}.new.$$"
    run ssh-keygen -t ed25519 -f "$tmpkey" -C "$comment"
    run mv -f -- "$tmpkey" "$keyfile"
    run mv -f -- "${tmpkey}.pub" "${keyfile}.pub"
  else
    run ssh-keygen -t ed25519 -f "$keyfile" -C "$comment"
  fi
  [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "keypair generated: ${keyfile} (+ ${keyfile}.pub)"

  if [[ -n "$copy_target" ]]; then
    need_cmd ssh-copy-id
    banner "Copy public key"
    c_info "target: $copy_target"
    # The key exists by now, so a "no" here is not "nothing was changed".
    confirm "Copy ${keyfile}.pub to ${copy_target}?" \
      || { c_warn "skipped copying the key to $copy_target"; exit 1; }
    run ssh-copy-id -i "${keyfile}.pub" "$copy_target"
    [[ "${DRY_RUN:-0}" == "1" ]] || c_ok "public key copied to $copy_target"
  fi
}

main "$@"
