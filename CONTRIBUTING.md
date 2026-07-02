# Contributing

Thanks for looking! This repo is a set of small, single-purpose shell tools that all
share one engine (`lib/common.sh`). Consistency is the whole point — new tools should
be indistinguishable from existing ones.

## Setup

```bash
pip install -r requirements-dev.txt        # pytest + ruff
sudo apt install bats shellcheck           # shell test harness + linter (Linux/WSL)
```

## Run the checks

Linux / WSL / macOS use `make`; Windows uses `tasks.ps1` — same target names.

```bash
make lint     # bash -n + shellcheck + ruff
make test     # bats + pytest
make all      # both
```

```powershell
.\tasks.ps1 all     # tools absent on Windows (shellcheck/bats) are skipped; run in CI
```

CI runs all of the above on every push and PR — a green tick means shellcheck-clean,
tests passing, and the Makefile valid.

## The tool contract

Every tool script **must**:

1. Start with `#!/usr/bin/env bash` and `set -euo pipefail`.
2. Source the shared engine and reuse it — never re-implement logging or guards:
   ```bash
   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)/common.sh"
   ```
3. Provide a `usage()` and handle `-h`/`--help` **before** any `need_cmd` guard, so
   help works without the tool's dependencies. (`tests/bats/help_smoke.bats` enforces
   this — see [DECISIONS.md](DECISIONS.md) D13.)
4. Guard destructive/root actions with `require_root` + `confirm`, and route side
   effects through `run` so `DRY_RUN=1` and `ASSUME_YES=1` work.
5. Be shellcheck-clean (`-e SC1091` is the only allowed exception — the runtime
   `source`).

## Adding a tool

- Drop it in the matching module folder (`01`–`05`); one tool = one file = one job.
- Add a row to that folder's `README.md` table and to the root `README.md` command index.
- Run `make lint test`. The `-h` smoke test picks up new scripts automatically.

## Project state

The lifecycle files at the repo root are the source of truth — read them before large
changes: `STATUS.md` (where things stand), `PROGRESS.md` (timeline), `DECISIONS.md`
(why things are the way they are), `CLAUDE_MEMORY.md` (rules & stack).
