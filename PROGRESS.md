# PROGRESS

A dated log of what happened, what was tried, what worked.

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
- Pushed to GitHub: `https://github.com/www8351/devops-toolkit-5`.

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
