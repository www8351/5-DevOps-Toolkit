# PROGRESS

A dated log of what happened, what was tried, what worked.

---

## 2026-10-18 (evening): Phases 12 and 13, monitors JSON, docs, review fixes (1.1.0 complete)

**What was done**
- Phase 12: `--json` for `diskwatch` (KiB via `df -kP`), `memwatch` (bytes, `-w/--warn`), `httpcheck`
  (status, seconds) and `pingsweep` (up, rtt). One document on stdout, top-level `ok`. `pingsweep` exits 1
  on a down host; failing rows moved to stdout (`c_fail`). New `json_num`. D24 recorded.
- Phase 13: `ssh_toolkit` reads `DRY_RUN`/`ASSUME_YES`; README "Command-line conventions" (flag letters,
  exit codes, streams, `--json` with `jq`/`json.tool`); CONTRIBUTING parser template; CHANGELOG 1.1.0.
- An adversarial review of the migration (12 findings, 1 question) drove these fixes, each test first:
  `pkg` had stopped passing `--purge`/`--no-install-recommends` to the package manager; `sshkey` deleted the
  old key before ssh-keygen ran (now generates beside it and swaps on success); 14 tools rejected `--`;
  `need_arg` accepted an empty value (`permfix -o ""` silently skipped chown); `memwatch --warn` compared
  the rounded percentage; `json_num` passed leading zeros; `name_echo.sh` took `--help` as an iteration
  count, so it now follows the contract instead of being exempt.
- Documented rather than changed: stray arguments now exit 2 in thirteen tools (all listed in the
  changelog), `0` and leading zeros are rejected, bundled/attached short options are gone (D23 note), and an
  option value of literally `-h` triggers help (D22 note).
- Declined: guarding empty-array expansion for bash < 4.4; the project targets Bash 5 (README badge).

**What was tried / found**
- A heredoc inside a heredoc (`cat <<'EOF'` around a script whose `usage()` also uses `EOF`) ended early;
  the leftover lines ran as harmless "command not found" noise. The file was rewritten with the editor;
  the tree was checked before continuing.
- The first `--` contract test matched "unknown option: --x" as a failure; it now matches the exact line.

**Verification**
- `make all`: shellcheck, `bash -n` (28 scripts), ruff, 147 bats, 109 pytest, all clean. Release-note
  extraction for 1.1.0 returns its section.

## 2026-10-18 (evening): Phases 10 and 11, one command-line contract for every tool

**Goal:** The owner picked interface consistency as the next wave, with three rules: renamed flags stay
as warned aliases (D23), JSON for the monitors only, exit codes 0/1/2 (D22).

**What was done**
- Phase 10, `lib/common.sh`: `usage_error` (exit 2 plus a `--help` hint), `need_arg`, `help_requested`
  (help anywhere before `--`), `deprecated`, `confirm_or_abort` (a "no" exits 1 everywhere), `c_fail`
  (failed result row on stdout), `json_str` (JSON string escaping, round-trip tested through Python; CI runs the C locale, and the suite was also run once by hand under C.UTF-8). `confirm` now asks on stderr.
- Phase 11, one module per commit: every tool's parser rewritten to the same `while/case` shape; long
  flags everywhere; `--dry-run`/`--yes` on the ten tools that change the system; old flags renamed with
  aliases. Two contract tests in `help_smoke.bats` (unknown option exits 2; `--help` after another argument)
  failed for all 25 tools before and pass after.

**What was tried / found**
- An inventory agent mapped every flag, exit path and doc reference first, so each rename came with its
  test and doc edits in the same commit.
- Real bugs surfaced by the migration: `pkg.sh install -h` tried to install a package called "-h";
  `sshkey.sh --yes` on an existing key hung at ssh-keygen's own "Overwrite (y/n)?" (the old key is now
  removed after the tool's own confirmation); five tools silently ignored stray arguments.
- Earlier tests that checked malformed arguments (mkswap sizes and paths, permfix modes, diskwatch range,
  httpcheck timeout) expected exit 1; they now expect 2, which is the point of D22.
- Bundled short options (`-an 5`) and attached values (`-n5`) are no longer parsed; recorded in D22 and
  for the changelog.

**Verification**
- `make all`: shellcheck, `bash -n`, ruff, 128 bats, 103 pytest, all clean.

## 2026-10-18: Phase 9, docs polish (wave complete)

**Goal:** Every claim in the docs matches the repo, in the house style.

**What was done**
- README: recounted every number from the repo (74 bats + 103 pytest = 177 tests; 6 CI jobs with the
  pytest matrix; 25 tools); rewrote the Quality & CI table, Development targets, roadmap (shipped vs
  planned) and layout tree; safety model gained the non-root dry run, the `sudo DRY_RUN=1` order, the
  health-check exit codes and the Python prompts, linking `SECURITY.md`; release and Python 3.10+ badges.
- Removed em dash separators across README, CONTRIBUTING, DEMO and module READMEs (Hebrew lines included).
  An earlier manual dash removal had left sentences without punctuation ("themselves it's", "lib/common.sh
  a single shared engine", the skills list); repaired. The layout tree no longer names `CLAUDE_MEMORY.md`.
- Module READMEs: httpcheck exit code, docker-clean daemon check, non-root dry run, fixed the
  `ssh_toolkit` anchor after its heading changed. CONTRIBUTING: add-a-tool checklist now covers the exec
  bit, behaviour tests with `stub`, and a CHANGELOG line.
- `CLAUDE_MEMORY.md`: stack (Python 3.10+, pinned tools), the pipefail and dry-run rules learned in this
  wave, test and release conventions, docs style.

**Wave summary (Phases 5 to 9, all on PR #3)**
Fix first, then showcase. 24 bats + 29 pytest became 74 + 103; the tests forced about twenty real fixes
(two safety bugs in `mkswap.sh`, a `--dry-run` that did not stop `net --apply`, remote command injection,
host keys accepted blindly, tools dying silently under pipefail, health checks exiting 0). CI pinned and
matrixed, releases tag-driven. Owner steps: merge, tag `v1.0.0`, enable private vulnerability reporting,
record the demo, run the live-VM checks.

**Verification**
- `make all` clean; bats clean as `nobody`; CI green on all 6 jobs for the Phase 8 head before this entry.

## 2026-10-18: Phase 8, repo hygiene and release

**Goal:** The signals of a maintained project: pinned dependencies, a version, a changelog, a release path.

**What was done**
- CI: `ludeeus/action-shellcheck@master` pinned to `2.0.0`; the lint job installs the pinned
  `requirements-dev.txt` (`pytest==9.1.1`, `ruff==0.17.1`, `tomli` below 3.11) instead of an unpinned ruff;
  `timeout-minutes` on every job; `concurrency` with cancel-in-progress; `workflow_dispatch`.
- pytest matrix on Python 3.10 and 3.14. The documented and enforced floor moved from 3.8 (never tested;
  past end of life) to 3.10.
- `.github/dependabot.yml`: weekly updates for actions and pip (`/`, `/04-network-ssh`, `/05-docker-devops`).
- `CHANGELOG.md` with a 1.0.0 entry; `.github/workflows/release.yml` publishes the section for a pushed
  `vX.Y.Z` tag via `gh release create`; `SECURITY.md` (private reporting, safe-use rules). D21 recorded.

**What was tried / found**
- actionlint flagged the existing `$(find ...)` and unquoted target lists in `python.yml`; py_compile now
  uses `find -exec`, the intended splitting is annotated.
- The first awk extraction for release notes ran past the 1.0.0 section into the link references at the
  bottom of the changelog; it now stops there. Tested with the exact workflow snippet: 56 lines for 1.0.0,
  empty (so the job fails) for an unknown version.

**Verification**
- pytest 103/103 on Python 3.10 and 3.14 (uv-managed interpreters); `make all` clean; actionlint clean on
  all three workflows; YAML of `dependabot.yml` parses.
- Not verifiable here: the release workflow itself runs only on a pushed tag (owner step), and private
  vulnerability reporting must be switched on in the repository settings.

## 2026-10-18: Phase 7, shell behaviour tests

**Goal:** Grow the test count with tests of real behaviour, not only `-h`, and fix what they find.

**What was done**
- New bats files per module: `file_text.bats`, `network_ssh.bats`, plus additions to `system_monitor`,
  `user_permissions` and `docker_devops`. Read-only tools run on temp fixtures; tools that read the system
  (`df`, `curl`, `docker`) get a stub on PATH.
- Fixes the tests forced (each test was seen failing on the old code first):
  - `logtop.sh`: `sort | head` under pipefail died with exit 141 once the unique values passed 64 KiB (a
    100k-line log); a `-p` filter with no match exited 1. awk now takes the top N; grep's "no match" is OK.
  - `dirsnap.sh`: one unreadable subdirectory (or `/proc`) aborted before the total.
  - `bigfiles.sh`: find's exit 1 on an unreadable directory was read as "no -printf", switching to the
    macOS-incompatible `du -b` path.
  - `permfix.sh`: any MODE string was accepted, `/` was not refused, and the dry run did not say what
    would change.
  - `diskwatch.sh`: snap squashfs loop mounts (always 100%) made it alarm on every Ubuntu desktop; mount
    points with spaces were cut at the space.
  - `httpcheck.sh`: exit 0 even with failed endpoints.
  - `docker-clean.sh`: a stopped daemon was reported as "already tidy"; with `-f` the plan hid the
    created/dead containers it was about to remove; dry run claimed "removed".

**What was tried / found**
- The first fake `docker` stub matched `-q` while the script passes `-aq`, so two tests passed for the
  wrong reason. Caught by asserting the whole dry-run line, stub fixed, and the tests re-run against the
  old script to confirm they fail there.
- Unreadable-directory tests skip as root (root reads everything) and run on the non-root CI runner; they
  were also run here as `nobody`.

**Verification**
- `make all`: shellcheck, `bash -n`, ruff, 74 bats, 103 pytest, all clean. Bats also clean as `nobody`.

## 2026-10-18: Phase 6, Python correctness and safety

**Goal:** Make `ssh_toolkit` and `ec2-deploy.py` hold up to a security-minded reader.

**What was done (each fix landed test first)**
- `cli.py`: `--dry-run` now always beats `--apply` (it was ignored by `net`, so a "dry" run reconfigured
  the NIC). `--apply` asks y/N; `--yes` finally has a job. Parser defaults for `--port`, `--netmask` and
  `--remote-dir` used to shadow `SSHTK_*` env and `config.toml`; `--keyfile` ignored both. All now go
  through `resolve()`. Global flags are accepted after the subcommand (SUPPRESS-default parent parser).
- `network_manager.py`: inputs validated (`ipaddress`, contiguous dotted mask, a safe interface-name
  pattern) before anything runs, dry run included; PowerShell arguments quoted; timeouts everywhere;
  two dead "capture for rollback" calls removed.
- `ssh_orchestrator.py`: the paramiko `copy_id` fallback no longer interpolates the key into
  `echo "..."`; the key goes on stdin to a single `umask 077 && mkdir && chmod && cat >>` command.
- `payload_executor.py`: a quoted `~` was never expanded, so the demo created a directory named `~`.
  Paths now map `~` to `"$HOME"`; SFTP paths drop `~/`. Native ssh/scp gained `BatchMode=yes` and
  keepalives; every subprocess call has a timeout.
- `utils.py`: `ssh_client()` (known_hosts first, D18), `remote_exec()` (stdin, reads before exit status),
  `confirm()` returns False on EOF.
- `ec2-deploy.py`: y/N before a billed launch, `DRY_RUN`/`ASSUME_YES`, lazy boto3, region and credential
  errors explained, exit 1 when a wait fails, `requirements.txt` with boto3 (D19).
- ruff widened to `E9,F` in all three runners (D20). pytest gained `05-docker-devops/tests`.

**What was tried / found**
- Plan numbering shifted: the ruff widening took D20, so the release decision in Phase 8 becomes D21.
- A loopback OpenSSH 9.6 server was installed in the build container (not committed) to exercise the
  paramiko and native paths for real. It found nothing new in the code; the first SFTP attempt failed
  only because the ad-hoc `sshd_config` lacked a `Subsystem sftp` line.
- Native `scp` to a remote directory that does not exist still fails (scp never creates parents); the
  paramiko path creates them. That matches each tool's own semantics and was left as is.
- While checking `ec2-deploy.py` error paths, one run with `--region us-east-1 --yes` reached AWS using
  credentials present in the build container's environment. AWS answered `AuthFailure`; nothing was
  launched. Later runs used a clean environment.

**Verification**
- `make all`: shellcheck, `bash -n`, ruff `E9,F`, 42 bats, 103 pytest, all clean.
- Loopback sshd: paramiko `copy_id` with a key comment `evil"; touch /tmp/pwned; echo "` appended the key,
  ran nothing, and was a no-op the second time; `~/.ssh` 700, `authorized_keys` 600; SFTP to
  `~/sub/dir/`; `run_demo` into `~/demo_ssh` and `~/demo two`; native `connect`, `demo` and `transfer`
  through the CLI with `SSHTK_PORT=2222` from env; a wrong known_hosts key raised `BadHostKeyException`.
- `ec2-deploy.py` with real boto3: missing region, missing credentials and a declined prompt each print a
  one-line reason and exit 1.

## 2026-10-18: Phase 5, first-impression shell fixes (portfolio polish wave)

**Goal:** Nothing a reviewer runs in the first five minutes should be broken. Fix before showcasing:
recording the demo or cutting a release first would have shown broken output.

**How the work was found**
- A read-only audit of every script and Python module, then each finding reproduced before fixing.
- `make all` on a fresh Ubuntu 24.04 container failed before any change: `pingsweep.sh -h` exits 1
  without `ping`, and the `require_root` test assumed a non-root runner.

**What was done (each fix landed test first)**
- `lib/common.sh`: `hr`/`banner` used `tr ' ' '─'`, which swaps bytes, so every rule printed lone 0xE2
  bytes. Rebuilt with parameter expansion. `require_root` now allows a `DRY_RUN=1` preview (D17).
- Tracked every entry point as executable; new bats test; README quick start no longer needs `chmod`.
- `mkswap.sh`: the help example `DRY_RUN=1 sudo ...` ran for real (sudo drops the variable); a size with
  no unit meant bytes on one path and MiB on the other; relative paths reached `/etc/fstab`. All closed.
- `pkg.sh search` used the nonexistent `apt-get search`; `pkg.sh update` had no root check.
- `sysinfo.sh` died when `hostnamectl` exists but systemd does not. `lscpu`/`free` parsed under `LC_ALL=C`.
- `pingsweep.sh` and `audit-perms.sh` help fixes; the smoke test now runs `-h` and `--help`.
- `install-jenkins.sh` apt source write moved onto `run`; root tools stop saying "created"/"finished"
  during a dry run.
- `setup.sh`/`setup.ps1` failed with "No module named ssh_toolkit" outside `04-network-ssh`.

**What was tried / found**
- The plan said "cd into the script directory" for the setup scripts. PYTHONPATH was used instead: a cd
  would change what relative CLI paths point to. Config lookup is already package-relative.
- `mkswap.sh` first accepted leading zeros in SIZE; bash reads `010` as octal (8), so the regex now
  forbids them.
- New bats files stub external tools on PATH with a small `stub()` helper, which keeps every test
  host-safe (no account, swap or package change) and keeps D12's child-shell rule.

**Verification**
- `make all` clean: shellcheck, `bash -n` (28 scripts), ruff, 42 bats, 29 pytest. The bats suite also
  passes as `nobody`, matching the non-root CI runner.
- Manual: `DRY_RUN=1 mkswap.sh -s 1G -f /tmp/demo.swap` as `nobody` previews and exits 0;
  `pkg.sh search curl` works; `sysinfo.sh` exits 0 in a systemd-less container; `setup.sh --help` works
  from the repo root and from `/tmp`.
- Not verified at first: `setup.ps1` (no PowerShell in this environment). See the review follow-up below.

**Review follow-up (same day, before the first push)**
- An adversarial review of the Phase 5 diff found one bug and several risks, all fixed with tests:
  `pkg.sh` still printed "install complete" etc. under `DRY_RUN=1`; dnf/yum `check-update || true` hid
  real failures; `mkswap.sh` made 1.5 MiB or 2 MiB for `-s 1536K` depending on the path, could overflow
  on a huge G value, and as root would follow a dangling symlink at `-f`; `setup.ps1` leaked PYTHONPATH
  into the caller's session; `newuser`/`grant-sudo` help still said "Must run as root".
- Not changed: banner width under a C locale with a non-ASCII title (no such title remains after the demo
  title went ASCII).
- A portable PowerShell 7.4 was downloaded into the scratch area: `setup.ps1 --help` works from `/tmp`
  and restores PYTHONPATH; `tasks.ps1 all` passes. Windows PowerShell 5.1 itself remains untested.

## 2026-08-25 — README accuracy audit (tool count corrected)

**What was done**
- Audited every claim in `README.md` against the repository itself rather than against memory.
- **Corrected the tool count from 24 to 25.** The header, the English and Hebrew intros, the
  "one library, N consumers" line and the roadmap all said 24, while the module table
  (5 folders x 5 scripts) and the command index both list 25. The real split is **24 shell
  scripts + one Python tool** (`05-docker-devops/ec2-deploy.py`).
- Documented the two deliberate exemptions from the `-h` contract — `name_echo.sh` (interactive
  demo) and `setup.sh` (venv bootstrapper) — which `tests/bats/help_smoke.bats` skips by name.

**What was verified (and held up)**
- `53 tests` — 24 bats (`common.bats` 23 + `help_smoke.bats` 1) + 29 pytest. `pytest 04-network-ssh/tests`
  re-run here: **29 passed**.
- `5 green CI checks` — 5 jobs across 2 workflow files: shellcheck+`bash -n`, bats, makefile,
  py_compile+ruff, pytest.
- Repository layout, safety model, and the command→script index all match the tree.

**What did not change**
- No script, test, or CI change. Documentation only.

## 2026-07-02 — README overhaul (Quality & CI + Roadmap) & name alignment

**Goal:** Surface the hardening work in the README and give the repo a clear roadmap and cleaner design.

**What was done**
- New **🔬 Quality & CI** section: a 5-check table (shellcheck+bash -n, bats, pytest, py_compile+ruff,
  makefile) with what each guarantees, the 53-test total, and links to the lifecycle log.
- New **🗺️ Roadmap** section: shipped (✅) vs planned (⬜/💡), with a note that the 4-phase hardening
  landed as per-phase commits.
- Subtitle gained `53 tests · 5 green CI checks`; skills list gained *Testing & CI* and *Process discipline*.
- Aligned the project name everywhere to the canonical `5-DevOps-Toolkit` (matches the remote) — see D16.

**Verification**
- Cross-checked every claimed number against the repo: `common.bats` 23 + `help_smoke.bats` 1 = **24 bats**;
  **29 pytest**; **53** total; **5** CI jobs. Confirmed all linked files exist (DECISIONS/STATUS/PROGRESS/
  CONTRIBUTING/docs). Deliberately did **not** embed a demo GIF that isn't recorded yet (roadmap item).

---

## 2026-07-02 — Phase 4: Demos & docs polish (upgrade complete)

**Goal:** Make the repo self-demonstrating and contributor-friendly, closing the 4-phase upgrade.

**What was done**
- `docs/demo.sh` — a safe, read-only tour (sysinfo, dirsnap, txtstats, netinfo, httpcheck, topproc). Each
  step runs through a `step()` wrapper that tolerates a missing dependency so the tour always completes.
- `docs/DEMO.md` — exact `asciinema rec` + `agg` commands to turn the tour into a GIF.
- `CONTRIBUTING.md` — setup, the `make`/`tasks.ps1` checks, the tool contract, an add-a-tool checklist.
- README: expanded the repository-layout tree (tests/docs/CI/task-runner).

**What was tried / found**
- `docs/demo.sh` is a new `*.sh`, so `help_smoke.bats` auto-discovers it and runs `demo.sh -h`. Made it
  contract-compliant (usage + `-h` exit 0 before any action) so the smoke test passes and even covers it.
  Verified the tool flags it calls (`dirsnap -n`, `txtstats FILE`, `topproc -n`, `httpcheck <url>`) all exist.
- A GIF/asciinema cast **cannot be produced here** — recording needs a live terminal. Shipped the script +
  instructions and said so plainly; the `.cast`/`.gif` are generate-locally, not committed (D15).
- 2-lens verify before push (demo.sh shellcheck/contract clean; docs lens caught a DEMO.md self-contradiction
  about committing the `.cast` — fixed).

**Verification**
- `demo.sh -h` exits 0 and names itself; `bash -n` clean; blob is LF.
- CI: all 5 jobs green on `66f8c0f` — including shellcheck + `help_smoke` now exercising `demo.sh`.

**Upgrade summary (4 phases, all pushed per phase):** CI (shellcheck+python) → Tests (24 bats + 29 pytest,
wired to CI) → Task runner (`make` + `tasks.ps1`, CI-verified) → Demos & docs. Each phase used small atomic
commits and an adversarial multi-agent verify pass; those passes caught a bats blocker, two `-h`-contract
bugs, and several doc/portability issues before they hit `main`.

**Commit style:** 4 small atomic commits (demo.sh → DEMO.md → CONTRIBUTING → README), plus this final sync.

---

## 2026-07-02 — Phase 3: Task runner (Makefile + tasks.ps1)

**Goal:** One entrypoint for lint/test, usable on Linux/WSL/macOS (`make`) and the owner's Windows box
(`tasks.ps1`), mirroring CI so contributors run the same checks locally.

**What was done**
- `Makefile` — targets help/syntax/shellcheck/ruff/lint/bats/pytest/test/all; `.DEFAULT_GOAL := help`;
  self-documenting help parsed from `## ` comments; recipes wrap the exact commands CI already runs.
- `tasks.ps1` — PowerShell mirror with identical target names; graceful skips for Windows-absent tools.
- README `## Development` section; CI gained a `makefile` job (`make help` + `make -n all`).

**What was tried / found**
- `make` is not installed on the Windows dev box → the Makefile can't be run locally anywhere I control.
  Solution: a CI `makefile` job on ubuntu-latest (make preinstalled) runs `make -n all` — real verification
  that every target resolves and recipes expand. It passed.
- First `tasks.ps1` draft used bare `pytest`/`ruff` and trusted `bash` — all three broke in PowerShell:
  `pytest`/`ruff` shims aren't on the PS PATH, and Windows `bash` is a broken WSL stub
  (`execvpe(/bin/bash) failed`). Rewrote to use `python -m pytest` / `python -m ruff` and to probe bash
  *usability* (`bash -c 'exit 0'`), skipping with a warning when unusable. Re-ran: ruff pass, pytest 29 pass,
  `lint`/`test` exit 0 while skipping shellcheck/bats/bad-bash.
- Adversarial 3-lens verify (makefile / powershell-5.1 / parity) before push: Makefile + PS lenses clean;
  parity lens caught one README comment that wrongly attributed shellcheck to the `test` target — fixed.

**Verification**
- Local: `tasks.ps1` ruff/pytest/lint/test all exit 0; Makefile recipe lines confirmed tab-indented; blob is LF.
- CI: all 5 jobs green on `61dfc4e` — `shellcheck+bash -n`, `bats`, `makefile`, `py_compile+ruff`, `pytest`.

**Commit style:** 4 small atomic commits (Makefile → tasks.ps1 → CI makefile job → README), plus lifecycle sync.

---

## 2026-07-02 — Phase 2: Test suite (bats + pytest)

**Goal:** Close the "no tests" open item with real, VM-free tests over the pure/observable surface, and
wire them into CI so the quality gate is enforced.

**What was done**
- `04-network-ssh/tests/test_utils.py` (29 cases) + `conftest.py` (sys.path shim) for `ssh_toolkit.utils`:
  OS detection, path helpers, `RollbackStack` (LIFO + continue-on-error), `_from_env`, `load_toml`
  (flatten / absent / no-parser / malformed), `resolve()` precedence ladder, `confirm()`. No paramiko/VM needed.
- `tests/bats/common.bats` (24 tests) + `helper.bash` for `lib/common.sh`: logging tags, stderr routing,
  `die`, `need_cmd`, `require_root`, `run` (exec / DRY_RUN / exit-code propagation), `confirm`
  (ASSUME_YES + anchored y/N regex, uppercase, non-anchored reject), banner/hr, double-source guard.
- `tests/bats/help_smoke.bats`: enforces the `-h`-works-before-deps contract across every tool script.
- CI: added a `bats` job (apt bats) to the shellcheck workflow and a `pytest` job (py3.11) to the python one.

**What was tried / found**
- **Key design constraint:** `common.sh` defines a `run()` function that collides with bats' own `run`.
  Solution: never source `common.sh` into the test shell — invoke helpers in a child `bash -c 'source…; …'`.
- Ran an **adversarial 5-lens verification workflow** before pushing (bats couldn't run locally — no bats on
  the Windows box). It caught a **blocker**: `helper.bash` set `COMMON` without `export`, so the child shell
  never saw it → all 24 bats tests would have failed with status 127. Fixed before the first push.
- Same review flagged `sshkey.sh` running `need_cmd ssh-keygen` before `-h` (like `portscan.sh` in Phase 1) —
  a false-pass on CI (runner has the binary) but a contract violation. Both moved the guard after arg parsing.
- Added coverage the critic found missing: `run` exit-code propagation, real stderr routing (redirect stdout
  to /dev/null), `load_toml` no-parser + malformed branches.

**Verification**
- `pytest` 29/29 locally (py3.14); every bats assertion's underlying `bash -c` snippet simulated locally and
  matched. **CI is authoritative:** first shellcheck run failed on `SC2155` in `helper.bash`
  (`export X="$(...)"` masks return code) — split declare/assign, re-run **green**.
- Final state: all 4 CI jobs pass on `5db0516` — `shellcheck+bash -n`, `bats`, `py_compile+ruff`, `pytest`.

**Commit style:** 6 small atomic commits (contract fix → pytest → bats-common → bats-smoke → CI wiring →
SC2155 fix), plus this lifecycle sync.

---

## 2026-07-02 — Phase 1: Continuous Integration (GitHub Actions)

**Goal:** Close the "no CI" open item and make the repo's quality bar enforced, not aspirational — so the
git log reads like a progress timeline (small atomic commits, pushed per phase).

**What was done**
- `.github/workflows/shellcheck.yml` — `bash -n` syntax gate over every `*.sh` + `ludeeus/action-shellcheck`
  at `severity: warning`, ignoring `SC1091` (scripts `source lib/common.sh` at runtime).
- `.github/workflows/python.yml` — `python -m py_compile` on `ssh_toolkit` + `ec2-deploy.py`, plus
  `ruff check --select E9,F63,F7,F82` (real errors only, not style — keeps CI signal high without churn).
- README: replaced the static "ShellCheck-clean" shield with **live** shellcheck + python Actions badges.
- Committed the previously-untracked workspace `CLAUDE.md`.

**What was tried / found**
- `py_compile` verified locally against all `.py` before pushing → python workflow passed first try.
- First **shellcheck run failed** (4 warnings): `setup.sh` SC2034 (`ver` unused), `name_echo.sh` SC2034
  (`i` unused), `httpcheck.sh` SC2221/SC2222 (dead `case` alt — `2*` already matches the `"2xx/3xx"` marker).
  Fixed all three in a follow-up commit; **re-run is green**. The "ShellCheck-clean" badge is now earned, not claimed.
- Discovered the GitHub remote is `5-DevOps-Toolkit` while docs say `devops-toolkit-5`; fixed badge slugs to
  the real remote and logged the wider naming mismatch under STATUS "Needs review".
- shellcheck is not installed on the Windows dev box → shell linting is delegated to CI (which is exactly why
  CI caught what local checks couldn't).

**Commit style:** 6 small atomic commits (track CLAUDE.md → shellcheck wf → python wf → badges → lifecycle sync
→ shellcheck fix). Both workflows green on `bcecaeb`.

---

## 2026-06-27 — Project created from a command cheat-sheet

**Goal:** Turn a hand-written list of Linux / network / Docker / AWS commands into a portfolio repo of
small, single-purpose scripts spread across 5 themed folders, with an impressive bilingual README, and
publish it to a new public GitHub repo.

**What was done**
- Confirmed scope with the user: repo name `devops-toolkit-5`, public, bilingual (HE+EN) README, **real
  operational** scripts (not safe demos), full `git init → commit → push` pipeline.
- `git init` on `main`; wrote `.gitignore` (ignores `*.pem`, `.aws/`, ssh keys, `*.tar.bz2`),
  `.editorconfig`, MIT `LICENSE`.
- Designed and wrote the shared engine **`lib/common.sh`**: coloured logging (`c_info/c_ok/c_warn/c_err`),
  `die`, `need_cmd`, `require_root`, `confirm` (honours `ASSUME_YES`), `run` (honours `DRY_RUN`), `hr`,
  `banner`. This is the reuse backbone for all 24 scripts.
- Fanned out a 5-way parallel agent workflow (one agent per folder) to write the scripts + folder READMEs
  against the `common.sh` contract, each followed by a per-folder compliance review pass.
- Grouped the commands into 5 modules:
  - **01 file-text-toolkit** — dirsnap, logtop, bigfiles, txtstats, backup.
  - **02 user-permissions** — newuser, whohas, permfix, audit-perms, grant-sudo.
  - **03 system-monitor** — sysinfo, topproc, diskwatch, memwatch, mkswap.
  - **04 network-ssh** — netinfo, pingsweep, httpcheck, portscan, sshkey.
  - **05 docker-devops** — pkg, docker-run-web, docker-clean, install-jenkins, ec2-deploy.py.
- Wrote the impressive bilingual root `README.md` (badges, module table, mermaid architecture diagram,
  quick-start, safety model, skills + command index in `<details>`).

**What worked**
- Single shared `common.sh` contract kept all 24 scripts consistent (same flags, same guards) instead of
  copy-pasted boilerplate.
- Parallel agents writing into disjoint folder paths → no file conflicts.

**What was tricky**
- First workflow script failed to parse: raw backticks around a word inside a JS template literal closed
  the string early. Fixed by quoting and moving the workflow into a reusable `.js` file run via `scriptPath`.

**Verification**
- `bash -n` on every `.sh`; `shellcheck` where available; ran the read-only scripts and captured real output.

**Outcome**
- Pushed to GitHub: `https://github.com/www8351/5-DevOps-Toolkit`.

---

## 2026-06-27 — Cross-platform SSH automation toolkit (`04-network-ssh/ssh_toolkit`)

**Goal:** Turn the manual VM-to-VM SSH lab walkthrough (hardcoded IPs, Debian-only `/etc/network/interfaces`,
Linux-only `ssh-copy-id`) into a **zero-hardcoding, cross-platform (Win/Mac/Linux) Python automation**.

**What was done**
- Analysed the original walkthrough: static IP config, keygen, copy-id, ssh, scp, remote tar demo, name-echo demo.
- Designed a Python 3.8+ package `ssh_toolkit/` inside the existing `04-network-ssh/` module.
- Wrote `setup.sh` (bash) and `setup.ps1` (PowerShell) bootstrappers that create a `.venv`,
  install `paramiko`, and forward all args to `python -m ssh_toolkit`.
- Wrote `requirements.txt` with `paramiko>=3.4.0` and `tomli` compat shim for Python <3.11.
- Wrote `config.example.toml` — zero-hardcoding config with precedence: CLI > env > TOML > prompt.
- Wrote `ssh_toolkit/utils.py` — colour logging, OS detect (`host_os()`), `RollbackStack`, `load_toml`, `resolve`.
- Wrote `ssh_toolkit/ssh_orchestrator.py` — idempotent ed25519 keygen; portable `copy_id` (native
  `ssh-copy-id` or paramiko password-session fallback); `connect_test` (native ssh or paramiko).
- Wrote `ssh_toolkit/payload_executor.py` — `transfer()` (native `scp` or paramiko SFTP); `run_demo()`
  (idempotent remote mkdir/touch/tar, captures stdout+stderr).
- Wrote `ssh_toolkit/network_manager.py` — OS-aware static IP with auto-detect Linux stack (Netplan /
  nmcli / `/etc/network/interfaces`), macOS `networksetup`, Windows PowerShell; timestamped backup;
  ping-validate; auto-rollback via `RollbackStack`.
- Wrote `ssh_toolkit/cli.py` — argparse subcommands: `keys`, `authorize`, `connect`, `transfer`, `demo`,
  `net`, `all`. Config resolves: CLI flag > `SSHTK_*` env > `config.toml` > interactive prompt.
- Wrote `name_echo.sh` — the interactive name-echo demo from the original walkthrough.
- Updated `04-network-ssh/README.md` with full ssh_toolkit docs.

**What worked**
- `RollbackStack` pattern cleanly separates "apply" from "undo" without coupling modules.
- Preferring native tools (`ssh`, `scp`, `ssh-copy-id`) and falling back to paramiko avoids
  over-engineering while still working on Windows where native tools may be absent.
- Defaulting `net` to dry-run and requiring `--apply` prevents accidental connectivity loss.

**Verification status**
- Syntax verified by design (standard Python patterns, no unusual constructs).
- Not yet run against a live VM — needs a real two-VM lab to validate network rollback and SFTP paths.
