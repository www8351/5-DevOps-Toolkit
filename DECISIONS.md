# DECISIONS

The decision log. Why things are the way they are, and what was rejected.

---

### D1 — One shared library (`lib/common.sh`), not standalone scripts
**Decision:** Every script sources a single shared engine for logging, guards and the `run`/`confirm`
wrappers.
**Why:** Demonstrates DRY composition and keeps 24 tools consistent (identical flags and safety behaviour).
**Rejected:** Fully self-contained scripts — simpler to copy one file, but duplicates boilerplate 24× and
drifts over time.
**Status:** Final.

---

### D2 — "Real operational" scripts with hard safety guards
**Decision:** Scripts perform the actual operations (`useradd`, `docker run`, `mkswap`, `apt install`…),
but gate every destructive/root action behind `require_root` + `confirm`, and support `DRY_RUN=1`.
**Why:** The user explicitly chose real tools over safe demos; guards make "real" responsible instead of
dangerous.
**Rejected:** Pure echo/demo scripts (too toothless for a portfolio); raw unguarded commands (unsafe).
**Status:** Final.

---

### D3 — Group the command list into exactly 5 themed folders
**Decision:** files/text, users/permissions, system/hardware, network/ssh, docker/devops.
**Why:** Matches the natural clusters in the source cheat-sheet and the user's "5 folders" request; each
folder reads as a coherent mini-toolkit.
**Rejected:** One folder per command (too granular); a single flat folder (no narrative).
**Status:** Final.

---

### D4 — `ec2-deploy` written in Python, everything else in Bash
**Decision:** The AWS/boto3 deploy tool is Python; the other 23 tools are Bash.
**Why:** boto3 is a Python library — forcing it into Bash via the AWS CLI would be clumsier and less
faithful to the original `boto3` notes.
**Status:** Final.

---

### D5 — Bilingual (Hebrew + English) README, public repo
**Decision:** Root README carries side-by-side HE/EN intro; repo is public.
**Why:** User is Hebrew-speaking and wants a portfolio piece; bilingual widens the audience.
**Status:** Final.

---

### D6 — Keep the `CLAUDE.md` lifecycle files at the repo root
**Decision:** `STATUS.md` / `PROGRESS.md` / `DECISIONS.md` / `CLAUDE_MEMORY.md` live at root and are
committed.
**Why:** Mandated by the workspace `CLAUDE.md` protocol; they also signal disciplined process to anyone
reading the repo.
**Revisitable:** Could later move under `docs/` if they clutter the root — not blocking.

---

### D8 — `ssh_toolkit` as a Python package, not a shell extension of `sshkey.sh`
**Decision:** The cross-platform automation lives in a new `ssh_toolkit/` Python package alongside the
existing `sshkey.sh` (which is kept as-is for simple Linux/macOS key generation).
**Why:** True Windows-native automation requires `ssh-copy-id` equivalent, SFTP, and PowerShell-based
NIC config — impossible to do cleanly in Bash. Python 3 is available everywhere and matches the
existing boto3/Python tooling in `05-docker-devops/ec2-deploy.py`.
**Rejected:** Bash-only extension — would require WSL or Git Bash on Windows (not truly native).
**Status:** Final.

---

### D9 — `net` subcommand defaults to dry-run; requires `--apply`
**Decision:** `python -m ssh_toolkit net` prints the plan but does NOT touch any NIC unless `--apply`
is passed. The `all` subcommand only runs the network step when `--with-network` is given.
**Why:** Misconfiguring a NIC can cut off remote access with no easy recovery. Dry-run-by-default
makes the tool safe to call freely without risk of host isolation.
**Rejected:** Always-apply (too dangerous), always-skip (the user explicitly asked for it).
**Status:** Final.

---

### D10 — Native tools first, paramiko fallback
**Decision:** Every SSH operation tries the native binary first (`ssh`, `scp`, `ssh-copy-id`) and
falls back to paramiko only when the binary is absent (e.g. Windows without OpenSSH).
**Why:** Native tools are battle-tested, respect `~/.ssh/config`, and avoid re-implementing TLS.
paramiko is only strictly needed for the password-based `copy_id` step on Windows.
**Rejected:** paramiko-only — adds complexity and loses native-tool compatibility with user's existing
configs. Subprocess-only — `ssh-copy-id` isn't on Windows.
**Status:** Final.

---

### D7 — Build via a parallel multi-agent workflow
**Decision:** One agent per folder wrote that folder's scripts + README, each followed by a review agent.
**Why:** 5 disjoint folders parallelise cleanly; the review pass catches contract violations before commit.
**Status:** Final for v1.

---

### D11 — CI on `main` via GitHub Actions (shellcheck + ruff), lenient by design
**Decision:** Two workflows run on push/PR to `main`: `shellcheck.yml` (`bash -n` + shellcheck at
`severity: warning`, `-e SC1091`) and `python.yml` (`py_compile` + `ruff` restricted to real-error rules
`E9,F63,F7,F82`).
**Why:** Enforces the "ShellCheck-clean" claim instead of trusting it. `SC1091` is ignored because scripts
`source lib/common.sh` at runtime (static analysis can't follow it). Ruff is scoped to real errors, not
style, so CI stays a meaningful gate without failing on cosmetic nits that would discourage commits.
**Rejected:** Full `ruff` default ruleset (too noisy for an existing codebase, would go red immediately);
no CI (leaves the badge as an unverified claim).
**Status:** Final; rules can tighten later once a baseline is clean.

---

### D12 — Test only the pure/observable surface; bats runs helpers in a child shell
**Decision:** Tests cover `lib/common.sh` (bats) and `ssh_toolkit.utils` (pytest) — logging, guards, `run`,
`confirm`, config precedence, `RollbackStack` — but **not** anything needing a live VM, AWS, or paramiko.
bats tests never `source common.sh` directly; they call helpers inside `bash -c 'source …; …'`.
**Why:** The VM/SSH/boto3 paths can't be validated without real infrastructure (see D9/D10) — testing them
would mean heavy mocking of low value. The pure surface is where regressions actually hide and is trivially
testable. The child-shell pattern is **required**, not stylistic: `common.sh` defines a `run()` that would
otherwise clobber bats' own `run` builtin and break the harness.
**Rejected:** Sourcing `common.sh` into the test shell (breaks bats `run`); mocking paramiko/boto3 for
end-to-end tests (brittle, low ROI); no tests (leaves the quality bar unenforced).
**Status:** Final. Live-VM/SFTP/network-rollback validation remains a manual step against a real two-VM lab.

---

### D13 — `-h`/usage must work before any dependency guard
**Decision:** Every tool prints usage and exits 0 on `-h` **without** requiring its runtime binaries;
`need_cmd` runs only after argument parsing. Enforced by `tests/bats/help_smoke.bats`.
**Why:** Help that fails when a dependency is absent is useless exactly when a user is trying to learn how to
install/use the tool. `portscan.sh` (Phase 1) and `sshkey.sh` (Phase 2) violated this and were fixed.
**Status:** Final; new tools must satisfy the smoke test.
