# Contributing

Thanks for looking! This repo is a set of small, single-purpose shell tools that all
share one engine (`lib/common.sh`). Consistency is the whole point: new tools should
be indistinguishable from existing ones.

## Setup

```bash
pip install -r requirements-dev.txt        # pinned pytest + ruff (Python 3.10+)
sudo apt install bats shellcheck           # shell test harness + linter (Linux/WSL)
```

## Run the checks

Linux / WSL / macOS use `make`; Windows uses `tasks.ps1`, with the same target names.

```bash
make lint     # bash -n + shellcheck + ruff
make test     # bats + pytest
make all      # both
```

```powershell
.\tasks.ps1 all     # tools absent on Windows (shellcheck/bats) are skipped; run in CI
```

CI runs all of the above on every push and PR. A green tick means shellcheck-clean,
tests passing, and the Makefile valid.

## The tool contract

Every tool script **must**:

1. Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
2. Source the shared engine and reuse it; never re-implement logging or guards:
   ```bash
   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
   ```
3. Provide a `usage()` and parse arguments with the shared shape below. Help must work
   **before** any `need_cmd` guard, so it works without the tool's dependencies.
   (`tests/bats/help_smoke.bats` enforces this; see [DECISIONS.md](DECISIONS.md) D13, D22.)
4. Guard destructive/root actions with `require_root` + `confirm_or_abort`, and route side
   effects through `run` so `--dry-run`/`DRY_RUN=1` and `--yes`/`ASSUME_YES=1` work.
5. Follow the command-line conventions in the root README: one meaning per flag letter,
   a long form for every flag, exit 0/1/2, results on stdout and everything else on stderr.
6. Be shellcheck-clean (`-e SC1091` is the only allowed exception: the runtime
   `source`).

The parser shape every tool uses:

```bash
main() {
  help_requested "$@" && { usage; exit 0; }

  local top=10
  local -a args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--top)  need_arg "$@"; top="$2"; shift 2 ;;
      --dry-run) export DRY_RUN=1; shift ;;      # only in tools that change the system
      --yes)     export ASSUME_YES=1; shift ;;
      --) shift; args+=("$@"); break ;;
      -*) usage_error "unknown option: $1" ;;    # exit 2
      *)  args+=("$1"); shift ;;
    esac
  done
  [[ "${#args[@]}" -le 1 ]] || usage_error "expected at most one PATH"
  [[ "$top" =~ ^[1-9][0-9]*$ ]] || usage_error "--top must be a positive integer"
  # ... die "..." (exit 1) for problems in the world, such as a missing file
}
```

Renaming a flag? Keep the old spelling working with `deprecated OLD NEW` (D23) and list it
under "Deprecated" in `CHANGELOG.md`.

## Adding a tool

- Drop it in the matching module folder (`01`–`05`); one tool = one file = one job.
- Commit it executable: `git update-index --chmod=+x path/to/tool.sh`.
- Add a row to that folder's `README.md` table and to the root `README.md` command index.
- Add behaviour tests to `tests/bats/<module>.bats`. Use temp fixtures under
  `$BATS_TEST_TMPDIR`, and replace system commands with `stub NAME 'body'` from
  `tests/bats/helper.bash` so a test never touches the host. Root tools are tested
  under `DRY_RUN=1`, which works without root.
- Add a line under `## [Unreleased]` in `CHANGELOG.md`.
- Run `make lint test`. The `-h`/`--help` and executable-bit checks pick up new scripts
  automatically.

## Project state

The lifecycle files at the repo root are the source of truth; read them before large
changes: `STATUS.md` (where things stand), `PROGRESS.md` (timeline), `DECISIONS.md`
(why things are the way they are), `CLAUDE_MEMORY.md` (rules & stack).
