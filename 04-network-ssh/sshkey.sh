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
  -f KEYFILE     private key path (default: ~/.ssh/id_ed25519)
  -C COMMENT     key comment (default: user@host)
  -c USER@HOST   copy the public key to USER@HOST after generating (ssh-copy-id)
  -h, --help     show this help and exit

Honours DRY_RUN=1 (print instead of run) and ASSUME_YES=1 (skip prompts).
EOF
}

main() {
  need_cmd ssh-keygen

  local keyfile="${HOME}/.ssh/id_ed25519"
  local comment=""
  local copy_target=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -f)
        [[ $# -ge 2 ]] || die "-f requires a KEYFILE argument"
        keyfile="$2"
        shift 2
        ;;
      -C)
        [[ $# -ge 2 ]] || die "-C requires a COMMENT argument"
        comment="$2"
        shift 2
        ;;
      -c)
        [[ $# -ge 2 ]] || die "-c requires a USER@HOST argument"
        copy_target="$2"
        shift 2
        ;;
      -*) die "unknown option: $1 (try -h)" ;;
      *) die "unexpected argument: $1 (try -h)" ;;
    esac
  done

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
    confirm "Overwrite existing key $keyfile?" || die "aborted by user"
  fi

  # Ensure the parent directory exists with sane permissions.
  local keydir
  keydir="$(dirname "$keyfile")"
  if [[ ! -d "$keydir" ]]; then
    run mkdir -p "$keydir"
    run chmod 700 "$keydir"
  fi

  run ssh-keygen -t ed25519 -f "$keyfile" -C "$comment"
  c_ok "keypair generated: ${keyfile} (+ ${keyfile}.pub)"

  if [[ -n "$copy_target" ]]; then
    need_cmd ssh-copy-id
    banner "Copy public key"
    c_info "target: $copy_target"
    if confirm "Copy ${keyfile}.pub to ${copy_target}?"; then
      run ssh-copy-id -i "${keyfile}.pub" "$copy_target"
      c_ok "public key copied to $copy_target"
    else
      c_warn "skipped copying key to $copy_target"
    fi
  fi
}

main "$@"
