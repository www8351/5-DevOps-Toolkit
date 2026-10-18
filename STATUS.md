# STATUS

_Last updated: 2026-10-18_

## Where the project stands
**2026-10-18: portfolio polish wave in progress (Phases 5 to 9).** The plan fixes what a reviewer
would hit in the first five minutes, then hardens the Python, widens the tests, adds release
hygiene and polishes the docs. **Phase 5 (first-impression shell fixes) is done** on branch
`ccr-dec6d5a6-417b42`: 42 bats + 29 pytest = 71 tests, `make all` clean as root and as a
non-root user. The README still states the old counts (53 tests); Phase 9 recounts them.

**v1 complete + hardened.** A 5-module DevOps shell toolkit is built, tested and pushed to GitHub as a
public repo. Now **CI-gated** (shellcheck + bats + pytest + Makefile-parse + ruff — all 5 jobs green),
**tested** (24 bats + 29 pytest = 53), with a **task runner** (`make` / `tasks.ps1`) and **contributor docs**
(`CONTRIBUTING.md`, `docs/demo.sh` + recording guide). The 4-phase upgrade (CI → Tests → Task runner →
Docs) is done; each phase landed as small atomic commits, pushed per phase.

**2026-08-25 — README claims re-audited against the repo.** The tool count was wrong everywhere it
was stated as a headline number: the toolkit ships **25 tools** (24 shell + `ec2-deploy.py`), not 24.
Fixed in the header, both intros, the DRY paragraph and the roadmap. Test and CI counts (53 tests,
5 CI jobs) were re-verified and are correct as written. Documentation only — no code change.

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

## Done (added 2026-10-18), Phase 5: first-impression shell fixes
- [x] `hr`/`banner` drew broken UTF-8 (byte-wise `tr`); now built with parameter expansion. Tests match exact characters.
- [x] All 28 `.sh` entry points and `ec2-deploy.py` tracked as `100755`; bats test guards it; README quick start lost its `chmod` step.
- [x] `require_root` lets a non-root user preview under `DRY_RUN=1` (D17). README quick start step 4 now works as a normal user.
- [x] `mkswap.sh`: help example fixed to `sudo DRY_RUN=1` (the old order ran for real); SIZE needs a unit; absolute path required.
- [x] `pkg.sh search` uses `apt-cache` (was `apt-get search`, exit 100); `pkg.sh update` needs root on apt.
- [x] `sysinfo.sh` survives a `hostnamectl` that cannot run (containers, WSL); `lscpu`/`free` parsed with `LC_ALL=C`.
- [x] `pingsweep.sh -h` works without `ping`; `audit-perms.sh --help` exits 0; smoke test covers `-h` and `--help`.
- [x] `install-jenkins.sh` writes its apt source through `run`; root tools stop claiming success under `DRY_RUN=1`.
- [x] `setup.sh`/`setup.ps1` run from any directory (PYTHONPATH, not cd).
- [x] New bats files: `system_monitor.bats`, `docker_devops.bats`, `user_permissions.bats`; `stub()` helper in `helper.bash`.

## Open / not done (user steps — need a human + real hardware)
- [ ] Record `docs/demo.cast` / `demo.gif` from a live terminal and embed the GIF in the README.
- [ ] `ssh_toolkit` live-VM smoke test (needs a real two-VM lab).
- [x] Repo-name mismatch resolved — canonical name is `5-DevOps-Toolkit` (the remote); all docs aligned (D16).

## Next best action
1. Phase 6: Python correctness and safety (`ssh_toolkit` CLI precedence, `--dry-run` gating `net`,
   remote injection, timeouts, host keys, `ec2-deploy.py` safety contract, pure pytest, ruff `F`).
2. Then Phases 7 to 9 per the approved plan (behaviour tests, repo hygiene and release, docs).
3. Human steps after the merge: record the demo GIF (only now that banners render correctly),
   push the `v1.0.0` tag, run `ssh_toolkit` against a real two-VM lab.

## Blockers / waiting on
None.

## Needs review
`04-network-ssh/setup.ps1` gained a PYTHONPATH line (Phase 5) but was not run: PowerShell is not
available in the build environment. Run `.\setup.ps1 --help` from the repo root on Windows once.

Destructive/root scripts (`newuser.sh`, `mkswap.sh`, `pkg.sh`, `install-jenkins.sh`, `grant-sudo.sh`) were
verified via `-h` and `DRY_RUN` only — they were **not** executed against a live system. Run them in a
throwaway VM/WSL before relying on them.
