#!/usr/bin/env bats
#
# Behaviour tests for 05-docker-devops. External tools (apt-get, apt-cache,
# id) are replaced by stubs on PATH, so nothing touches the host.

load helper

PKG="$REPO_ROOT/05-docker-devops/pkg.sh"

@test "pkg search uses apt-cache, since apt-get has no search command" {
  stub apt-get
  stub apt-cache
  run bash "$PKG" search curl
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:apt-cache search curl"* ]]
}

@test "pkg search is a query, so DRY_RUN=1 still runs it" {
  stub apt-get
  stub apt-cache
  DRY_RUN=1 run bash "$PKG" search curl
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:apt-cache search curl"* ]]
}

@test "pkg update with apt-get needs root" {
  stub apt-get
  stub id 'echo 1000'
  run bash "$PKG" update
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs root"* ]]
  [[ "$output" != *"stub:apt-get"* ]]
}

@test "pkg update runs apt-get update as root" {
  stub apt-get
  stub id 'echo 0'
  run bash "$PKG" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:apt-get update"* ]]
}

@test "install-jenkins dry run routes the repo file write through run" {
  stub apt-get
  stub curl
  DRY_RUN=1 ASSUME_YES=1 run bash "$REPO_ROOT/05-docker-devops/install-jenkins.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] sh -c"*"/etc/apt/sources.list.d/jenkins.list"* ]]
  [[ "$output" == *"[dry-run] apt-get install -y jenkins"* ]]
  [[ "$output" == *"nothing was changed"* ]]
  [[ "$output" != *"installation finished"* ]]
  [[ "$output" != *"stub:"* ]]
}

@test "pkg install dry run previews without claiming success" {
  stub apt-get
  stub id 'echo 1000'
  DRY_RUN=1 ASSUME_YES=1 run bash "$PKG" install curl
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] apt-get install -y curl"* ]]
  [[ "$output" != *"install complete"* ]]
  [[ "$output" != *"stub:apt-get"* ]]
}

# On an apt host the real apt-get would win detection, so these tests run with
# PATH narrowed to the stubs plus dirname (needed to locate lib/common.sh).
@test "pkg update on dnf accepts exit 100 (updates available)" {
  stub dnf 'echo "stub:dnf $*"; exit 100'
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/stubs/dirname"
  PATH="$BATS_TEST_TMPDIR/stubs" run "$BASH" "$PKG" update
  [ "$status" -eq 0 ]
  [[ "$output" == *"stub:dnf check-update"* ]]
  [[ "$output" == *"index refreshed"* ]]
}

@test "pkg update on dnf reports a real failure" {
  stub dnf 'exit 1'
  ln -s "$(command -v dirname)" "$BATS_TEST_TMPDIR/stubs/dirname"
  PATH="$BATS_TEST_TMPDIR/stubs" run "$BASH" "$PKG" update
  [ "$status" -eq 1 ]
  [[ "$output" != *"index refreshed"* ]]
}

# ── docker-clean ──────────────────────────────────────────────────────────────
CLEAN="$REPO_ROOT/05-docker-devops/docker-clean.sh"

# Fake docker with one exited container, one "created" container and one
# dangling image. Removal commands are only ever reached under DRY_RUN=1.
FAKE_DOCKER='case "$1" in
  info) exit 0 ;;
  ps)
    if [[ "$*" == *"-aq"* && "$*" == *"status=created"* ]]; then echo c2;
    elif [[ "$*" == *"-aq"* ]]; then echo c1;
    elif [[ "$*" == *"status=created"* ]]; then echo "  c1  nginx  web"; echo "  c2  redis  cache";
    else echo "  c1  nginx  web"; fi ;;
  images)
    if [[ "$*" == *"-q"* ]]; then echo i1; else echo "  i1  <none>:<none>"; fi ;;
  *) echo "stub:docker $*" ;;
esac'

@test "docker-clean fails when the daemon is unreachable" {
  # It used to swallow the error and report "already tidy".
  stub docker 'exit 1'
  run bash "$CLEAN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Docker daemon"* ]]
  [[ "$output" != *"tidy"* ]]
}

@test "docker-clean dry run previews removals without claiming them" {
  stub docker "$FAKE_DOCKER"
  DRY_RUN=1 ASSUME_YES=1 run bash "$CLEAN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] docker rm c1"$'\n'* ]]
  [[ "$output" == *"[dry-run] docker rmi i1"$'\n'* ]]
  [[ "$output" != *"removed"* ]]
  [[ "$output" != *"stub:docker rm"* ]]
}

@test "docker-clean -f also lists created and dead containers in the plan" {
  stub docker "$FAKE_DOCKER"
  DRY_RUN=1 ASSUME_YES=1 run bash "$CLEAN" -f
  [ "$status" -eq 0 ]
  [[ "$output" == *"c2  redis  cache"* ]]
  [[ "$output" == *"[dry-run] docker rm c1 c2"$'\n'* ]]
}
