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

@test "httpcheck rejects a non-numeric timeout" {
  run bash "$HTTPCHECK" -t soon https://a.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"timeout must be"* ]]
}
