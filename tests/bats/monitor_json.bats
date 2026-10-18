#!/usr/bin/env bats
#
# Machine output and exit codes for the four monitors (D22): diskwatch,
# memwatch, httpcheck and pingsweep. System commands are stubs; every --json
# document is parsed with Python's json module.

bats_require_minimum_version 1.5.0   # for run --separate-stderr
load helper

# assert_json — the whole of $output is one valid JSON document.
assert_json() {
  python3 -c 'import json, sys; json.loads(sys.stdin.read())' <<<"$output"
}

# jq_py EXPR — evaluate a Python expression against the parsed JSON as `d`.
jq_py() {
  python3 -c 'import json, sys; d = json.loads(sys.stdin.read()); print(eval(sys.argv[1]))' "$1" <<<"$output"
}

# ── diskwatch ─────────────────────────────────────────────────────────────────
# df stub: KiB columns for -kP (machine mode), human sizes otherwise.
FAKE_DF='if [[ "$*" == *k* ]]; then
  echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
  echo "/dev/sda1 52428800 20971520 31457280 40% /"
  echo "/dev/sdb1 104857600 99614720 5242880 95% /mnt/my disk"
  echo "tmpfs 1048576 1048576 0 100% /run"
else
  echo "Filesystem Size Used Avail Use% Mounted on"
  echo "/dev/sda1 50G 20G 30G 40% /"
  echo "/dev/sdb1 100G 95G 5G 95% /mnt/my disk"
  echo "tmpfs 1.0G 1.0G 0 100% /run"
fi'

@test "diskwatch --json emits one document with every real filesystem" {
  stub df "$FAKE_DF"
  run --separate-stderr bash "$REPO_ROOT/03-system-monitor/diskwatch.sh" --json --warn 90
  [ "$status" -eq 1 ]
  assert_json
  [ "$(jq_py 'd["ok"]')" = "False" ]
  [ "$(jq_py 'd["warn_pct"]')" = "90" ]
  [ "$(jq_py 'len(d["filesystems"])')" = "2" ]
  [ "$(jq_py '[f["mount"] for f in d["filesystems"] if f["over"]]')" = "['/mnt/my disk']" ]
  [ "$(jq_py 'd["filesystems"][0]["size_kib"]')" = "52428800" ]
}

@test "diskwatch --json below the threshold is ok and exits 0" {
  stub df "$FAKE_DF"
  run --separate-stderr bash "$REPO_ROOT/03-system-monitor/diskwatch.sh" --json --warn 99
  [ "$status" -eq 0 ]
  [ "$(jq_py 'd["ok"]')" = "True" ]
}

@test "diskwatch prints a failing row on stdout, not split across streams" {
  stub df "$FAKE_DF"
  run --separate-stderr bash "$REPO_ROOT/03-system-monitor/diskwatch.sh" --warn 90
  [ "$status" -eq 1 ]
  [[ "$output" == *"/mnt/my disk"*"95%"* ]]
}

# ── memwatch ──────────────────────────────────────────────────────────────────
FAKE_FREE='echo "              total        used        free"
echo "Mem:          1000         900         100"
echo "Swap:          200          50         150"'

@test "memwatch --json reports RAM and swap usage" {
  stub free "$FAKE_FREE"
  run --separate-stderr bash "$REPO_ROOT/03-system-monitor/memwatch.sh" --json
  [ "$status" -eq 0 ]
  assert_json
  [ "$(jq_py 'd["mem"]["used_pct"]')" = "90.0" ]
  [ "$(jq_py 'd["swap"]["total_bytes"]')" = "200" ]
  [ "$(jq_py 'd["ok"]')" = "True" ]
  [ "$(jq_py 'd["warn_pct"]')" = "None" ]
}

@test "memwatch --warn alerts with exit 1 at or above the threshold" {
  stub free "$FAKE_FREE"
  run bash "$REPO_ROOT/03-system-monitor/memwatch.sh" --warn 85
  [ "$status" -eq 1 ]
  [[ "$output" == *"90.0%"* ]]
  run bash "$REPO_ROOT/03-system-monitor/memwatch.sh" --warn 95
  [ "$status" -eq 0 ]
  run --separate-stderr bash "$REPO_ROOT/03-system-monitor/memwatch.sh" --warn 85 --json
  [ "$status" -eq 1 ]
  [ "$(jq_py 'd["ok"]')" = "False" ]
}

@test "memwatch --warn outside 1-100 is a usage error" {
  run bash "$REPO_ROOT/03-system-monitor/memwatch.sh" --warn 0
  [ "$status" -eq 2 ]
}

# ── httpcheck ─────────────────────────────────────────────────────────────────
FAKE_CURL='url="${*: -1}"
case "$url" in
  *down*) printf "000 0.000"; exit 7 ;;
  *500*)  printf "500 0.050" ;;
  *)      printf "200 0.123" ;;
esac'

@test "httpcheck --json lists each URL with status and time" {
  stub curl "$FAKE_CURL"
  run --separate-stderr bash "$REPO_ROOT/04-network-ssh/httpcheck.sh" --json \
    https://a.example 'https://b.example/"quoted"' https://down.example
  [ "$status" -eq 1 ]
  assert_json
  [ "$(jq_py 'd["ok"]')" = "False" ]
  [ "$(jq_py '[r["status"] for r in d["results"]]')" = "[200, 200, None]" ]
  [ "$(jq_py 'd["results"][0]["time_s"]')" = "0.123" ]
  [ "$(jq_py 'd["results"][1]["url"]')" = 'https://b.example/"quoted"' ]
}

@test "httpcheck prints a failing row on stdout" {
  stub curl "$FAKE_CURL"
  run --separate-stderr bash "$REPO_ROOT/04-network-ssh/httpcheck.sh" https://down.example
  [ "$status" -eq 1 ]
  [[ "$output" == *"https://down.example"*"FAIL"* ]]
}

# ── pingsweep ─────────────────────────────────────────────────────────────────
FAKE_PING='host="${*: -1}"
case "$host" in
  *down*) exit 1 ;;
  *) echo "64 bytes from $host: icmp_seq=1 ttl=64 time=1.25 ms" ;;
esac'

@test "pingsweep exits 1 when a host is down, 0 when all are up" {
  stub ping "$FAKE_PING"
  run bash "$REPO_ROOT/04-network-ssh/pingsweep.sh" a.example down.example
  [ "$status" -eq 1 ]
  run bash "$REPO_ROOT/04-network-ssh/pingsweep.sh" a.example b.example
  [ "$status" -eq 0 ]
}

@test "pingsweep --json lists each host with state and round-trip time" {
  stub ping "$FAKE_PING"
  run --separate-stderr bash "$REPO_ROOT/04-network-ssh/pingsweep.sh" --json a.example down.example
  [ "$status" -eq 1 ]
  assert_json
  [ "$(jq_py '[(h["host"], h["up"], h["rtt_ms"]) for h in d["hosts"]]')" = "[('a.example', True, 1.25), ('down.example', False, None)]" ]
}

@test "pingsweep prints a DOWN row on stdout" {
  stub ping "$FAKE_PING"
  run --separate-stderr bash "$REPO_ROOT/04-network-ssh/pingsweep.sh" down.example
  [[ "$output" == *"down.example"*"DOWN"* ]]
}
