# STATUS

_Last updated: 2026-07-02_

## Where the project stands
**v1 complete + hardened.** A 5-module DevOps shell toolkit is built, tested and pushed to GitHub as a
public repo. Now **CI-gated** (shellcheck + bats + pytest + Makefile-parse + ruff — all 5 jobs green),
**tested** (24 bats + 29 pytest = 53), with a **task runner** (`make` / `tasks.ps1`) and **contributor docs**
(`CONTRIBUTING.md`, `docs/demo.sh` + recording guide). The 4-phase upgrade (CI → Tests → Task runner →
Docs) is done; each phase landed as small atomic commits, pushed per phase.

## Done
- [x] `git init` on `main`, repo scaffolding (`.gitignore`, `.editorconfig`, `LICENSE` MIT).
- [x] Shared engine `lib/common.sh` (logging, guards, `run`/`confirm`, `banner`).
- [x] 24 single-purpose scripts across 5 folders + one Python (`ec2-deploy.py`).
- [x] Per-folder `README.md` for all 5 modules.
- [x] Impressive bilingual (HE/EN) root `README.md` with badges, module table, mermaid diagram.
- [x] Lifecycle files (this set) bootstrapped per `CLAUDE.md` protocol.
- [x] Syntax + shellcheck pass; non-destructive smoke tests.
- [x] Published to GitHub (`gh repo create … --public --push`).

## Done (added 2026-06-27)
- [x] `04-network-ssh/ssh_toolkit/` — cross-platform Python SSH automation package.
- [x] `setup.sh` + `setup.ps1` bootstrappers (venv creation, dep install, arg forwarding).
- [x] `requirements.txt` (paramiko + tomli compat shim).
- [x] `config.example.toml` — zero-hardcoding config template.
- [x] `name_echo.sh` — interactive name-echo demo from lab walkthrough.
- [x] `04-network-ssh/README.md` updated with full ssh_toolkit docs.
- [x] Lifecycle files (`STATUS`, `PROGRESS`, `DECISIONS`) updated.

## Done (added 2026-07-02) — Phase 1: CI
- [x] `.github/workflows/shellcheck.yml` — `shellcheck` (warning, -e SC1091) + `bash -n` on push/PR.
- [x] `.github/workflows/python.yml` — `py_compile` + `ruff` (real errors) for `ssh_toolkit` + `ec2-deploy.py`.
- [x] README badges switched to live Actions status; badge repo slug fixed to real remote `5-DevOps-Toolkit`.
- [x] Committed workspace `CLAUDE.md` (lifecycle protocol now tracked).

## Done (added 2026-07-02) — Phase 2: Tests
- [x] `tests/bats/common.bats` — 24 bats unit tests for `lib/common.sh` (child-shell pattern avoids `run()` clash).
- [x] `tests/bats/help_smoke.bats` — `-h` contract smoke over all tool scripts (helpers excluded).
- [x] `04-network-ssh/tests/test_utils.py` — 29 pytest cases for `ssh_toolkit.utils` (pure surface).
- [x] `requirements-dev.txt` (`pytest`, `ruff`); bats + pytest jobs wired into CI — all 4 CI jobs green.
- [x] Fixed `portscan.sh` + `sshkey.sh`: `-h` now works before `need_cmd` (help-before-deps contract).
- [x] Verified via adversarial multi-agent review + real CI run (bats caught the `COMMON`-export blocker pre-merge).

## Done (added 2026-07-02) — Phase 3: Task runner
- [x] `Makefile` — help/syntax/shellcheck/ruff/lint/bats/pytest/test/all; mirrors CI; self-documenting help.
- [x] `tasks.ps1` — Windows PowerShell mirror (same targets); `python -m` for py tools; skips Win-absent tools.
- [x] CI `makefile` job (`make help` + `make -n all`) proves the Makefile parses/resolves — all 5 jobs green.
- [x] README `## Development` section documents both runners.

## Done (added 2026-07-02) — Phase 4: Demos & docs
- [x] `docs/demo.sh` — safe read-only tour of the tools (contract-compliant `-h`; steps tolerate missing deps).
- [x] `docs/DEMO.md` — asciinema/agg recording instructions (recording is a user step — can't be automated).
- [x] `CONTRIBUTING.md` — setup, checks, tool contract, add-a-tool checklist.
- [x] README layout tree expanded (tests/docs/CI/task-runner); all 5 CI jobs still green.

## Open / not done (user steps — need a human + real hardware)
- [ ] Record `docs/demo.cast` / `demo.gif` from a live terminal and embed the GIF in the README.
- [ ] `ssh_toolkit` live-VM smoke test (needs a real two-VM lab).
- [ ] Resolve the repo-name mismatch (`5-DevOps-Toolkit` remote vs `devops-toolkit-5` in docs) — see Needs review.

## Next best action
The 4-phase upgrade is complete. Remaining items all need a human:
1. Record the demo GIF (`docs/DEMO.md`) and embed it in the README.
2. Copy `config.example.toml` → `config.toml`, fill in host/user; run `./setup.sh all …` on a Linux VM.
3. Decide the canonical repo name and align docs (see Needs review).

## Blockers / waiting on
None.

## Needs review
**Repo-name mismatch:** GitHub remote is `www8351/5-DevOps-Toolkit`, but README (clone URL, layout tree)
and lifecycle files call the project `devops-toolkit-5`. Badges were fixed to the real slug; the clone URL
and prose still say `devops-toolkit-5`. Decide the canonical name and align.

Destructive/root scripts (`newuser.sh`, `mkswap.sh`, `pkg.sh`, `install-jenkins.sh`, `grant-sudo.sh`) were
verified via `-h` and `DRY_RUN` only — they were **not** executed against a live system. Run them in a
throwaway VM/WSL before relying on them.
