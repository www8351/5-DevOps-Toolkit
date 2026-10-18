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
