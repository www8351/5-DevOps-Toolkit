#!/usr/bin/env bats
#
# Behaviour tests for 01-file-text-toolkit. Every test works on fixtures in
# its own temp dir, so nothing outside BATS_TEST_TMPDIR is read or written.

load helper

TOOLS="$REPO_ROOT/01-file-text-toolkit"

# ── txtstats ──────────────────────────────────────────────────────────────────
@test "txtstats counts lines, words, characters and the longest line" {
  printf 'one two\nthree\nfour five six\n' >"$BATS_TEST_TMPDIR/t.txt"
  run bash "$TOOLS/txtstats.sh" -n 1 "$BATS_TEST_TMPDIR/t.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lines:           3"* ]]
  [[ "$output" == *"Words:           6"* ]]
  [[ "$output" == *"Characters:      28"* ]]
  [[ "$output" == *"Longest line:    13"* ]]
}

@test "txtstats rejects a missing file" {
  run bash "$TOOLS/txtstats.sh" "$BATS_TEST_TMPDIR/nope.txt"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a regular file"* ]]
}

# ── logtop ────────────────────────────────────────────────────────────────────
@test "logtop ranks the most frequent values of a field" {
  printf '1.1.1.1 GET\n2.2.2.2 GET\n1.1.1.1 POST\n1.1.1.1 GET\n' >"$BATS_TEST_TMPDIR/a.log"
  run bash "$TOOLS/logtop.sh" -n 1 "$BATS_TEST_TMPDIR/a.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"3          | 1.1.1.1"* ]]
  [[ "$output" != *"2.2.2.2"* ]]
}

@test "logtop survives a log larger than a pipe buffer" {
  # head used to close the pipe early; sort died of SIGPIPE and pipefail
  # turned that into a silent exit 141.
  seq 1 100000 | awk '{print "host"$1" GET"}' >"$BATS_TEST_TMPDIR/big.log"
  run bash "$TOOLS/logtop.sh" -n 3 "$BATS_TEST_TMPDIR/big.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lines considered: 100000"* ]]
}

@test "logtop with a filter that matches nothing reports zero lines" {
  printf '1.1.1.1 GET\n' >"$BATS_TEST_TMPDIR/a.log"
  run bash "$TOOLS/logtop.sh" -p NOMATCH "$BATS_TEST_TMPDIR/a.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Lines considered: 0"* ]]
}

# ── bigfiles ──────────────────────────────────────────────────────────────────
@test "bigfiles lists the largest files first" {
  mkdir -p "$BATS_TEST_TMPDIR/tree/sub"
  head -c 3000 /dev/zero >"$BATS_TEST_TMPDIR/tree/mid.bin"
  head -c 9000 /dev/zero >"$BATS_TEST_TMPDIR/tree/sub/big.bin"
  head -c 100 /dev/zero >"$BATS_TEST_TMPDIR/tree/small.bin"
  run bash "$TOOLS/bigfiles.sh" -n 2 "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"big.bin"*"mid.bin"* ]]
  [[ "$output" != *"small.bin"* ]]
}

@test "bigfiles keeps GNU find when a subdirectory is unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads every directory"
  mkdir -p "$BATS_TEST_TMPDIR/tree/locked"
  head -c 5000 /dev/zero >"$BATS_TEST_TMPDIR/tree/a.bin"
  chmod 000 "$BATS_TEST_TMPDIR/tree/locked"
  run bash "$TOOLS/bigfiles.sh" "$BATS_TEST_TMPDIR/tree"
  chmod 755 "$BATS_TEST_TMPDIR/tree/locked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.bin"* ]]
  [[ "$output" != *"falling back"* ]]
}

# ── dirsnap ───────────────────────────────────────────────────────────────────
@test "dirsnap ranks subdirectories and prints a total" {
  mkdir -p "$BATS_TEST_TMPDIR/tree/big" "$BATS_TEST_TMPDIR/tree/small" "$BATS_TEST_TMPDIR/tree/.hidden"
  head -c 200000 /dev/zero >"$BATS_TEST_TMPDIR/tree/big/f"
  head -c 10 /dev/zero >"$BATS_TEST_TMPDIR/tree/small/f"
  run bash "$TOOLS/dirsnap.sh" -n 1 "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/big"* ]]
  [[ "$output" != *"/small"* ]]
  [[ "$output" != *".hidden"* ]]
  [[ "$output" == *"Total size of"* ]]
}

@test "dirsnap finishes when some subdirectories are unreadable" {
  [ "$(id -u)" -ne 0 ] || skip "root reads every directory"
  mkdir -p "$BATS_TEST_TMPDIR/tree/open/inner" "$BATS_TEST_TMPDIR/tree/locked/inner"
  chmod 000 "$BATS_TEST_TMPDIR/tree/locked"
  run bash "$TOOLS/dirsnap.sh" "$BATS_TEST_TMPDIR/tree"
  chmod 755 "$BATS_TEST_TMPDIR/tree/locked"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total size of"* ]]
}

# ── backup ────────────────────────────────────────────────────────────────────
@test "backup round trip restores the same content" {
  mkdir -p "$BATS_TEST_TMPDIR/src/data" "$BATS_TEST_TMPDIR/out" "$BATS_TEST_TMPDIR/restore"
  echo "payload" >"$BATS_TEST_TMPDIR/src/data/file.txt"
  cd "$BATS_TEST_TMPDIR/src"
  run bash "$TOOLS/backup.sh" data "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  local archive
  archive="$(ls "$BATS_TEST_TMPDIR"/out/data-*.tar.bz2)"
  ASSUME_YES=1 run bash "$TOOLS/backup.sh" --extract "$archive" "$BATS_TEST_TMPDIR/restore"
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/restore/data/file.txt")" = "payload" ]
}

@test "backup dry run creates no archive" {
  mkdir -p "$BATS_TEST_TMPDIR/src" "$BATS_TEST_TMPDIR/out"
  DRY_RUN=1 run bash "$TOOLS/backup.sh" "$BATS_TEST_TMPDIR/src" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] tar -cjvf"* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

# ── uniform interface (D22, D23) ──────────────────────────────────────────────
@test "txtstats accepts --lines and rejects a stray argument with exit 2" {
  printf 'a\nb\nc\n' >"$BATS_TEST_TMPDIR/t.txt"
  run bash "$TOOLS/txtstats.sh" --lines 1 "$BATS_TEST_TMPDIR/t.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Head (first 1 lines)"* ]]
  run bash "$TOOLS/txtstats.sh" "$BATS_TEST_TMPDIR/t.txt" extra
  [ "$status" -eq 2 ]
  run bash "$TOOLS/txtstats.sh" -n 0 "$BATS_TEST_TMPDIR/t.txt"
  [ "$status" -eq 2 ]
}

@test "logtop --field and --grep are the new names" {
  printf 'x 1.1.1.1\ny 2.2.2.2\nx 1.1.1.1\n' >"$BATS_TEST_TMPDIR/a.log"
  run bash "$TOOLS/logtop.sh" --field 2 --grep x --top 1 "$BATS_TEST_TMPDIR/a.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2          | 1.1.1.1"* ]]
  [[ "$output" != *"deprecated"* ]]
}

@test "logtop -f and -p still work as deprecated aliases with a warning" {
  printf 'x 1.1.1.1\ny 2.2.2.2\nx 1.1.1.1\n' >"$BATS_TEST_TMPDIR/a.log"
  run bash "$TOOLS/logtop.sh" -f 2 -p x "$BATS_TEST_TMPDIR/a.log"
  [ "$status" -eq 0 ]
  [[ "$output" == *"2          | 1.1.1.1"* ]]
  [[ "$output" == *"-f is deprecated, use -k/--field"* ]]
  [[ "$output" == *"-p is deprecated, use -g/--grep"* ]]
}

@test "logtop without a FILE is a usage error" {
  run bash "$TOOLS/logtop.sh" --top 3
  [ "$status" -eq 2 ]
}

@test "bigfiles accepts --top and --size" {
  mkdir -p "$BATS_TEST_TMPDIR/tree"
  head -c 9000 /dev/zero >"$BATS_TEST_TMPDIR/tree/big.bin"
  head -c 10 /dev/zero >"$BATS_TEST_TMPDIR/tree/tiny.bin"
  run bash "$TOOLS/bigfiles.sh" --top 5 --size +1k "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"big.bin"* ]]
  [[ "$output" != *"tiny.bin"* ]]
}

@test "dirsnap --all includes hidden directories" {
  mkdir -p "$BATS_TEST_TMPDIR/tree/.hidden"
  run bash "$TOOLS/dirsnap.sh" --all "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *".hidden"* ]]
}

@test "dirsnap with two paths is a usage error" {
  run bash "$TOOLS/dirsnap.sh" "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
}

@test "backup --dry-run is the same as DRY_RUN=1" {
  mkdir -p "$BATS_TEST_TMPDIR/src" "$BATS_TEST_TMPDIR/out"
  run bash "$TOOLS/backup.sh" --dry-run "$BATS_TEST_TMPDIR/src" "$BATS_TEST_TMPDIR/out"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] tar -cjvf"* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/out")" ]
}

@test "backup --extract declined exits 1 and extracts nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/src/data" "$BATS_TEST_TMPDIR/restore"
  echo x >"$BATS_TEST_TMPDIR/src/data/f"
  tar -cjf "$BATS_TEST_TMPDIR/a.tar.bz2" -C "$BATS_TEST_TMPDIR/src" data
  run bash "$TOOLS/backup.sh" --extract "$BATS_TEST_TMPDIR/a.tar.bz2" "$BATS_TEST_TMPDIR/restore" <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing was changed"* ]]
  [ -z "$(ls -A "$BATS_TEST_TMPDIR/restore")" ]
}

@test "backup with three arguments is a usage error" {
  run bash "$TOOLS/backup.sh" a b c
  [ "$status" -eq 2 ]
}
