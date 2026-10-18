#!/usr/bin/env bats
#
# Behaviour tests for 04-network-ssh. curl is a stub whose answer depends on
# the URL, so no request leaves the machine.

load helper

HTTPCHECK="$REPO_ROOT/04-network-ssh/httpcheck.sh"

# Fake curl: prints "<code> <seconds>" like `curl -w '%{http_code} %{time_total}'`.
# The URL is the last argument.
FAKE_CURL='url="${*: -1}"
case "$url" in
  *down*) printf "000 0.000"; exit 7 ;;
  *500*)  printf "500 0.050" ;;
  *)      printf "200 0.123" ;;
esac'

@test "httpcheck exits 0 when every URL answers 2xx/3xx" {
  stub curl "$FAKE_CURL"
  run bash "$HTTPCHECK" https://a.example https://b.example
  [ "$status" -eq 0 ]
  [[ "$output" == *"200"*"0.123s"* ]]
  [[ "$output" == *"summary: 2 ok, 0 failed, 2 total"* ]]
}

@test "httpcheck exits 1 when an endpoint is unreachable" {
  stub curl "$FAKE_CURL"
  run bash "$HTTPCHECK" https://a.example https://down.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"summary: 1 ok, 1 failed, 2 total"* ]]
}

@test "httpcheck exits 1 on a 5xx answer" {
  stub curl "$FAKE_CURL"
  run bash "$HTTPCHECK" https://500.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"500"* ]]
}

@test "httpcheck rejects a non-numeric timeout (usage error, exit 2)" {
  run bash "$HTTPCHECK" -t soon https://a.example
  [ "$status" -eq 2 ]
  [[ "$output" == *"timeout must be"* ]]
}

# ── uniform interface (D22, D23) ──────────────────────────────────────────────
@test "httpcheck accepts --timeout and needs at least one URL" {
  stub curl "$FAKE_CURL"
  run bash "$HTTPCHECK" --timeout 3 https://a.example
  [ "$status" -eq 0 ]
  run bash "$HTTPCHECK" --timeout 3
  [ "$status" -eq 2 ]
}

@test "pingsweep reads --file and rejects an empty host list with exit 2" {
  stub ping 'echo "64 bytes from x: icmp_seq=1 ttl=64 time=1.25 ms"'
  printf 'a.example\n# comment\nb.example\n' >"$BATS_TEST_TMPDIR/hosts"
  run bash "$REPO_ROOT/04-network-ssh/pingsweep.sh" --file "$BATS_TEST_TMPDIR/hosts"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.example"*"b.example"* ]]
  run bash "$REPO_ROOT/04-network-ssh/pingsweep.sh"
  [ "$status" -eq 2 ]
}

@test "portscan takes exactly one target" {
  stub nmap
  run bash "$REPO_ROOT/04-network-ssh/portscan.sh" --ports 22,80 host-a host-b
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/04-network-ssh/portscan.sh" --ports 22,80
  [ "$status" -eq 2 ]
  run bash "$REPO_ROOT/04-network-ssh/portscan.sh" --ports 22,80 host-a
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:nmap -Pn -sV -p 22,80 host-a"* ]]
}

@test "netinfo rejects a stray argument with exit 2" {
  run bash "$REPO_ROOT/04-network-ssh/netinfo.sh" stray
  [ "$status" -eq 2 ]
}

# sshkey runs against a temp HOME and a stub ssh-keygen, so no real key is made.
@test "sshkey --copy-to is the new name; -c still works with a warning" {
  export HOME="$BATS_TEST_TMPDIR/home"
  stub ssh-keygen
  stub ssh-copy-id
  run bash "$REPO_ROOT/04-network-ssh/sshkey.sh" --file "$HOME/.ssh/k" --copy-to me@host --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] ssh-copy-id -i $HOME/.ssh/k.pub me@host"* ]]
  [[ "$output" != *"keypair generated"* ]]
  run bash "$REPO_ROOT/04-network-ssh/sshkey.sh" --file "$HOME/.ssh/k" -c me@host --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"-c is deprecated, use --copy-to"* ]]
}

@test "sshkey declining to overwrite an existing key exits 1" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/k"
  stub ssh-keygen
  run bash "$REPO_ROOT/04-network-ssh/sshkey.sh" --file "$HOME/.ssh/k" <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing was changed"* ]]
  [[ "$output" != *"stub:ssh-keygen"* ]]
}

@test "sshkey removes the old key after a yes, so ssh-keygen never asks again" {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.ssh"
  touch "$HOME/.ssh/k" "$HOME/.ssh/k.pub"
  # ssh-keygen refuses (exits 1) if the file still exists, like it would hang
  # on its own "Overwrite (y/n)?" prompt in a non-interactive run.
  stub ssh-keygen 'for a; do f="$a"; done; if [ -e "$HOME/.ssh/k" ]; then exit 1; fi; echo "stub:ssh-keygen $*"'
  run bash "$REPO_ROOT/04-network-ssh/sshkey.sh" --file "$HOME/.ssh/k" --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:ssh-keygen -t ed25519 -f $HOME/.ssh/k"* ]]
}

@test "name_echo repeats the name N times and validates N" {
  run bash "$REPO_ROOT/04-network-ssh/name_echo.sh" 3 <<< "bob"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'bob bob bob$' <<<"$output")" -eq 3 ]
  run bash "$REPO_ROOT/04-network-ssh/name_echo.sh" many </dev/null
  [ "$status" -eq 2 ]
}
