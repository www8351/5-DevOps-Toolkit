#!/usr/bin/env bats
#
# Behaviour tests for 03-system-monitor. Root tools are exercised under
# DRY_RUN=1, which require_root allows for a normal user (D17), so nothing
# touches the host.

load helper

MKSWAP="$REPO_ROOT/03-system-monitor/mkswap.sh"

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
