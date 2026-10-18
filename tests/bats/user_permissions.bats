#!/usr/bin/env bats
#
# Behaviour tests for 02-user-permissions. Account tools run under DRY_RUN=1
# as a stubbed non-root user (D17), with getent and the mutating commands
# stubbed on PATH, so no account is ever touched.

load helper

@test "newuser dry run previews useradd without claiming success" {
  stub id 'echo 1000'
  stub getent 'exit 2'    # user does not exist yet
  stub useradd
  DRY_RUN=1 ASSUME_YES=1 run bash "$REPO_ROOT/02-user-permissions/newuser.sh" -u bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] useradd -m -d /home/bob -s /bin/bash -U bob"* ]]
  [[ "$output" != *"created"* ]]
  [[ "$output" != *"stub:useradd"* ]]
}

@test "grant-sudo dry run previews usermod without claiming success" {
  stub id 'echo 1000'
  stub getent 'exit 0'    # user and the sudo group both exist
  stub usermod
  DRY_RUN=1 ASSUME_YES=1 run bash "$REPO_ROOT/02-user-permissions/grant-sudo.sh" -u alice
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] usermod -aG sudo alice"* ]]
  [[ "$output" != *"added 'alice'"* ]]
  [[ "$output" != *"stub:usermod"* ]]
}

# ── audit-perms ───────────────────────────────────────────────────────────────
@test "audit-perms reports world-writable and setuid files" {
  mkdir -p "$BATS_TEST_TMPDIR/tree"
  touch "$BATS_TEST_TMPDIR/tree/open.txt" "$BATS_TEST_TMPDIR/tree/suid.bin" "$BATS_TEST_TMPDIR/tree/fine.txt"
  chmod 666 "$BATS_TEST_TMPDIR/tree/open.txt"
  chmod 4755 "$BATS_TEST_TMPDIR/tree/suid.bin"
  chmod 644 "$BATS_TEST_TMPDIR/tree/fine.txt"
  run bash "$REPO_ROOT/02-user-permissions/audit-perms.sh" "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"World-writable files"*"open.txt"*"SUID files"*"suid.bin"* ]]
  [[ "$output" != *"fine.txt"* ]]
}

# ── permfix ───────────────────────────────────────────────────────────────────
PERMFIX="$REPO_ROOT/02-user-permissions/permfix.sh"

make_tree() {
  mkdir -p "$BATS_TEST_TMPDIR/tree/sub"
  touch "$BATS_TEST_TMPDIR/tree/a.txt" "$BATS_TEST_TMPDIR/tree/sub/b.txt"
  chmod 700 "$BATS_TEST_TMPDIR/tree/sub"
  chmod 600 "$BATS_TEST_TMPDIR/tree/a.txt" "$BATS_TEST_TMPDIR/tree/sub/b.txt"
}

mode_of() { stat -c '%a' "$1"; }

@test "permfix defaults to a dry run that says what would change" {
  make_tree
  run bash "$PERMFIX" "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would change: 1 directory(ies), 2 file(s)"* ]]
  [[ "$output" == *"[dry-run] find"* ]]
  [ "$(mode_of "$BATS_TEST_TMPDIR/tree/a.txt")" = "600" ]
}

@test "permfix --execute normalises modes" {
  make_tree
  ASSUME_YES=1 run bash "$PERMFIX" --execute "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$BATS_TEST_TMPDIR/tree/sub")" = "755" ]
  [ "$(mode_of "$BATS_TEST_TMPDIR/tree/sub/b.txt")" = "644" ]
}

@test "permfix rejects a mode that is not octal (usage error, exit 2)" {
  make_tree
  run bash "$PERMFIX" --files 999 "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 2 ]
  [[ "$output" == *"octal"* ]]
}

@test "permfix refuses the filesystem root" {
  # Dry run (no --execute): even if the guard were missing, nothing changes.
  run bash "$PERMFIX" /
  [ "$status" -eq 1 ]
  [[ "$output" == *"refusing"* ]]
}

# ── uniform interface (D22, D23) ──────────────────────────────────────────────
NEWUSER="$REPO_ROOT/02-user-permissions/newuser.sh"
GRANT="$REPO_ROOT/02-user-permissions/grant-sudo.sh"

@test "newuser long flags and --dry-run/--yes work like the env toggles" {
  stub id 'echo 1000'
  stub getent 'exit 2'
  stub useradd
  run bash "$NEWUSER" --user bob --shell /bin/zsh --home /srv/bob --no-user-group --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] useradd -m -d /srv/bob -s /bin/zsh -N bob"* ]]
  [[ "$output" != *"deprecated"* ]]
}

@test "newuser -s and -d still work as deprecated aliases with a warning" {
  stub id 'echo 1000'
  stub getent 'exit 2'
  stub useradd
  DRY_RUN=1 ASSUME_YES=1 run bash "$NEWUSER" -u bob -s /bin/zsh -d /srv/bob
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] useradd -m -d /srv/bob -s /bin/zsh -U bob"* ]]
  [[ "$output" == *"-s is deprecated, use --shell"* ]]
  [[ "$output" == *"-d is deprecated, use --home"* ]]
}

@test "newuser without --user is a usage error" {
  run bash "$NEWUSER" --shell /bin/sh
  [ "$status" -eq 2 ]
}

@test "newuser declined at the prompt exits 1" {
  stub id 'echo 1000'
  stub getent 'exit 2'
  stub useradd
  run bash "$NEWUSER" --dry-run --user bob <<< "n"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing was changed"* ]]
}

@test "grant-sudo accepts --user and rejects a stray argument" {
  stub id 'echo 1000'
  stub getent 'exit 0'
  stub usermod
  run bash "$GRANT" --user alice --dry-run --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] usermod -aG sudo alice"* ]]
  run bash "$GRANT" --user alice stray
  [ "$status" -eq 2 ]
}

@test "whohas rejects more than one user" {
  run bash "$REPO_ROOT/02-user-permissions/whohas.sh" root nobody
  [ "$status" -eq 2 ]
}

@test "audit-perms accepts --limit and rejects a negative limit" {
  mkdir -p "$BATS_TEST_TMPDIR/tree"
  run bash "$REPO_ROOT/02-user-permissions/audit-perms.sh" --limit 5 "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  run bash "$REPO_ROOT/02-user-permissions/audit-perms.sh" --limit -1 "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 2 ]
}

@test "permfix --dry-run wins over --execute" {
  make_tree
  run bash "$PERMFIX" --execute --dry-run "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 0 ]
  [ "$(mode_of "$BATS_TEST_TMPDIR/tree/a.txt")" = "600" ]
}

@test "permfix with an empty --owner is a usage error, not a silent skip" {
  make_tree
  run bash "$PERMFIX" -o "" "$BATS_TEST_TMPDIR/tree"
  [ "$status" -eq 2 ]
}
