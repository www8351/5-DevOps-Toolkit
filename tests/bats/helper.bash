# Shared bats helper: locate the repo root and force deterministic (colourless)
# output for assertions.
#
# NOTE: lib/common.sh defines a `run()` function whose name collides with bats'
# own `run`. We therefore never `source` common.sh into the test shell — every
# test invokes helpers inside a child `bash -c 'source ...; <call>'` so bats'
# `run` stays intact and $status/$output remain meaningful.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO_ROOT
export NO_COLOR=1   # common.sh -> empty colour palette -> exact, stable strings

export COMMON="$REPO_ROOT/lib/common.sh"   # must be exported: child `bash -c` reads it

# stub NAME [BODY] — put a fake NAME first on PATH for this test. Without a
# BODY the fake just echoes "stub:NAME <args>" so a test can assert the call.
stub() {
  local name="$1" body="${2:-}"
  local dir="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$dir"
  [[ -n "$body" ]] || body="echo \"stub:$name \$*\""
  # Absolute bash path, so a stub still runs when a test narrows PATH.
  printf '#!%s\n%s\n' "$BASH" "$body" >"$dir/$name"
  chmod +x "$dir/$name"
  [[ ":$PATH:" == *":$dir:"* ]] || export PATH="$dir:$PATH"
}
