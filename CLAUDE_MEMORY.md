# CLAUDE_MEMORY

Long-term memory, core preferences and persistent rules for this project.

---

## Project identity
- **Name:** `5-DevOps-Toolkit` — a portfolio of small, single-purpose Linux/DevOps scripts built from the
  owner's hand-written command cheat-sheet.
- **Owner / GitHub:** `www8351` · repo: `https://github.com/www8351/5-DevOps-Toolkit` (public).
- **Audience:** recruiters / engineers reading the repo as a skills showcase, plus the owner as a daily
  command reference.

## Technical stack & constraints
- **Bash** (`#!/usr/bin/env bash`, `set -euo pipefail`) for 24 tools; **Python 3.10+** for `ssh_toolkit` and
  `ec2-deploy.py` (boto3). CI tests Python 3.10 and 3.14; dev tools are pinned in `requirements-dev.txt`.
- **Target OS:** Linux / WSL / Ubuntu. The owner develops on **Windows** — read-only scripts run in Git
  Bash, root/system scripts run in WSL or a Linux VM.
- **Every script MUST** source `lib/common.sh` and reuse its helpers — never re-implement logging or guards.
- **Every script MUST** ship `-h/--help`, validate args, and (when destructive) use `require_root` +
  `confirm` + `run` (so `DRY_RUN=1` and `ASSUME_YES=1` work).
- **Quality bar:** shellcheck-clean, quoted expansions, `[[ ]]` tests, `$(...)` over backticks; ruff `E9,F`.
- **Pipelines under pipefail:** never end a pipeline with `head` after a producer that can outgrow a pipe
  buffer (use `awk 'NR<=n'`), and tolerate the expected non-zero status of `grep` (1 = no match) and
  `du`/`find` (1 = some entry unreadable). These killed tools silently before (Phase 7).
- **Under `DRY_RUN=1`** a root tool may run as a normal user (D17), so every side effect must go through
  `run`, and success lines must not print during a dry run.
- **Python tools** follow the same contract: `-h` without optional deps, a y/N prompt before anything
  costly or disruptive, `DRY_RUN`/`ASSUME_YES` env toggles, timeouts on every subprocess call.

## Architectural rules
- 5 themed folders (`01`–`05`); one tool = one file = one job.
- New tools go into the matching folder, follow the canonical template, are committed executable, and get
  a row in that folder's README table + the root README command index.
- Every tool gets behaviour tests in `tests/bats/<module>.bats` (temp fixtures, `stub` for system commands;
  never touch the host) or pytest for Python; each user-visible change gets a `CHANGELOG.md` line.
- Releases: owner pushes a `vX.Y.Z` tag; the release workflow publishes that CHANGELOG section (D21).
- Secrets never committed — `.gitignore` already blocks `*.pem`, `.aws/`, ssh keys, archives.

## Communication preferences (owner)
- Hebrew-speaking; README and user-facing docs are bilingual HE/EN.
- Docs style: no em dashes or hyphens as separators; README never mentions AI tooling or `CLAUDE*` files.
- Prefers direct, concise, no-fluff responses (caveman-style brevity is welcome in chat; code/commits/PRs
  stay normal and professional).

## Lifecycle protocol (enforced)
- Keep `STATUS.md`, `PROGRESS.md`, `DECISIONS.md`, this file, and `README.md` in sync automatically:
  - code change / task done → update `STATUS.md` + append dated `PROGRESS.md` entry.
  - architectural shift / rejected path → `DECISIONS.md`.
  - persona / rule / stack change → this file / `README.md`.
