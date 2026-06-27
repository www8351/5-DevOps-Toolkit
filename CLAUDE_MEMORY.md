# CLAUDE_MEMORY

Long-term memory, core preferences and persistent rules for this project.

---

## Project identity
- **Name:** `devops-toolkit-5` — a portfolio of small, single-purpose Linux/DevOps scripts built from the
  owner's hand-written command cheat-sheet.
- **Owner / GitHub:** `www8351` · repo: `https://github.com/www8351/devops-toolkit-5` (public).
- **Audience:** recruiters / engineers reading the repo as a skills showcase, plus the owner as a daily
  command reference.

## Technical stack & constraints
- **Bash** (`#!/usr/bin/env bash`, `set -euo pipefail`) for 23 tools; **Python 3 + boto3** for `ec2-deploy.py`.
- **Target OS:** Linux / WSL / Ubuntu. The owner develops on **Windows** — read-only scripts run in Git
  Bash, root/system scripts run in WSL or a Linux VM.
- **Every script MUST** source `lib/common.sh` and reuse its helpers — never re-implement logging or guards.
- **Every script MUST** ship `-h/--help`, validate args, and (when destructive) use `require_root` +
  `confirm` + `run` (so `DRY_RUN=1` and `ASSUME_YES=1` work).
- **Quality bar:** shellcheck-clean, quoted expansions, `[[ ]]` tests, `$(...)` over backticks.

## Architectural rules
- 5 themed folders (`01`–`05`); one tool = one file = one job.
- New tools go into the matching folder, follow the canonical template, and get a row in that folder's
  README table + the root README command index.
- Secrets never committed — `.gitignore` already blocks `*.pem`, `.aws/`, ssh keys, archives.

## Communication preferences (owner)
- Hebrew-speaking; README and user-facing docs are bilingual HE/EN.
- Prefers direct, concise, no-fluff responses (caveman-style brevity is welcome in chat; code/commits/PRs
  stay normal and professional).

## Lifecycle protocol (enforced)
- Keep `STATUS.md`, `PROGRESS.md`, `DECISIONS.md`, this file, and `README.md` in sync automatically:
  - code change / task done → update `STATUS.md` + append dated `PROGRESS.md` entry.
  - architectural shift / rejected path → `DECISIONS.md`.
  - persona / rule / stack change → this file / `README.md`.
