#!/usr/bin/env bats
#
# Behaviour tests for 03-system-monitor. Root tools are exercised under
# DRY_RUN=1, which require_root allows for a normal user (D17), so nothing
# touches the host.

load helper

MKSWAP="$REPO_ROOT/03-system-monitor/mkswap.sh"

setup() {
  # mkswap.sh checks for these before it previews. Stubs keep the tests from
  # depending on /usr/sbin being on a non-root PATH; swapon --show lists nothing.
  stub mkswap
  stub swapon ':'
  stub fallocate
}

@test "mkswap rejects a size without a unit" {
  # A bare number meant bytes to fallocate but MiB to the dd fallback.
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 1048576 -f "$BATS_TEST_TMPDIR/s.swap"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SIZE"* ]]
}

@test "mkswap rejects a zero size" {
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 0G -f "$BATS_TEST_TMPDIR/s.swap"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SIZE"* ]]
}

@test "mkswap rejects a size below 1M, which mkswap itself would refuse" {
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 512K -f "$BATS_TEST_TMPDIR/s.swap"
  [ "$status" -eq 1 ]
  [[ "$output" == *"too small"* ]]
}

@test "mkswap rejects a size long enough to overflow the arithmetic" {
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 18014398509481985G -f "$BATS_TEST_TMPDIR/s.swap"
  [ "$status" -eq 1 ]
  [[ "$output" == *"invalid SIZE"* ]]
}

@test "mkswap refuses a dangling symlink, which root would follow" {
  ln -s "$BATS_TEST_TMPDIR/target" "$BATS_TEST_TMPDIR/link.swap"
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 1G -f "$BATS_TEST_TMPDIR/link.swap"
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing to overwrite"* ]]
}

@test "mkswap rejects a relative swapfile path" {
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 1G -f relative.swap
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute"* ]]
}

@test "mkswap dry run previews every step and creates nothing" {
  local file="$BATS_TEST_TMPDIR/s.swap"
  DRY_RUN=1 ASSUME_YES=1 run bash "$MKSWAP" -s 1G -f "$file" --persist
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] fallocate -l 1G $file"* ]]
  [[ "$output" == *"[dry-run] mkswap $file"* ]]
  [[ "$output" == *"[dry-run] swapon $file"* ]]
  [[ "$output" == *"/etc/fstab"* ]]
  [[ "$output" == *"nothing was changed"* ]]
  [[ "$output" != *"swapfile ready"* ]]
  [ ! -e "$file" ]
}

@test "mkswap help shows DRY_RUN after sudo, where sudo keeps it" {
  run bash "$MKSWAP" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"sudo DRY_RUN=1"* ]]
  [[ "$output" != *"DRY_RUN=1 sudo"* ]]
}

# A fake free(1) that prints translated row labels unless LC_ALL=C, like a
# localized procps does. Only the C labels let the tools find their rows.
LOCALIZED_FREE='if [[ "${LC_ALL:-}" == C ]]; then m=Mem; s=Swap; else m=Speicher; s=Auslager; fi
echo "              total        used        free"
echo "$m:          1000         250         750"
echo "$s:           200          50         150"'

@test "sysinfo falls back when hostnamectl is installed but cannot run" {
  # Containers and WSL ship hostnamectl without systemd; it exits 1.
  stub hostnamectl 'echo "System has not been booted with systemd" >&2; exit 1'
  run bash "$REPO_ROOT/03-system-monitor/sysinfo.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Hostname:"* ]]
  [[ "$output" == *"Kernel / OS"* ]]
  [[ "$output" == *"Uptime / Load"* ]]
}

@test "sysinfo reads lscpu with C labels on a localized host" {
  stub lscpu 'if [[ "${LC_ALL:-}" == C ]]; then echo "Architecture: x86_64"; else echo "Architektur: x86_64"; fi'
  run bash "$REPO_ROOT/03-system-monitor/sysinfo.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Architecture: x86_64"* ]]
}

@test "memwatch computes usage with C labels on a localized host" {
  stub free "$LOCALIZED_FREE"
  run bash "$REPO_ROOT/03-system-monitor/memwatch.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RAM used:  25.0%"* ]]
  [[ "$output" == *"Swap used: 25.0%"* ]]
}
