# Shared bats helper: locate the repo root and force deterministic (colourless)
# output for assertions.
#
# NOTE: lib/common.sh defines a `run()` function whose name collides with bats'
# own `run`. We therefore never `source` common.sh into the test shell — every
# test invokes helpers inside a child `bash -c 'source ...; <call>'` so bats'
# `run` stays intact and $status/$output remain meaningful.

export REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export NO_COLOR=1   # common.sh -> empty colour palette -> exact, stable strings

export COMMON="$REPO_ROOT/lib/common.sh"   # must be exported: child `bash -c` reads it
