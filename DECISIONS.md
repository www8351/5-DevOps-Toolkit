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

---

### D14 — Makefile as the CI mirror; `tasks.ps1` as the Windows twin
**Decision:** A `Makefile` wraps the exact lint/test commands CI runs (single set of target names), and a
`tasks.ps1` mirrors it for Windows PowerShell. Windows-absent tools (shellcheck, bats) and an unusable
`bash` are **skipped with a warning**, not treated as failures, so `lint`/`test` still exit 0 on Windows.
Python tools are invoked via `python -m pytest` / `python -m ruff` (the launcher is reliably on PATH; the
bare shims often are not). A CI `makefile` job (`make -n all`) proves the Makefile stays valid.
**Why:** Contributors get one obvious command per platform; the owner develops on Windows where `make`,
`shellcheck`, `bats` are typically absent and `bash` may be a broken WSL stub — hard-failing there would make
the runner useless. Skipping-with-warning keeps it usable while CI remains the authoritative gate.
**Rejected:** Makefile-only (unusable on the owner's Windows box); duplicating command strings across CI +
Makefile + docs with no cross-check (drift — the CI `makefile` job guards against it); hard-failing on
missing Windows tools (turns a convenience into a blocker).
**Status:** Final.

---

### D15 — Ship a demo *script*, not a checked-in GIF
**Decision:** The demo is `docs/demo.sh` (a real, read-only, re-runnable tour) plus `docs/DEMO.md` with the
exact `asciinema` + `agg` commands. The `.cast`/`.gif` are generated locally by the user and are **not**
committed. `demo.sh` follows the tool contract (`-h` before deps) so `help_smoke.bats` covers it.
**Why:** A recording can't be produced in this environment (no live terminal), and a binary GIF bloats git
history. A script is reviewable, testable, stays correct as tools change, and lets anyone regenerate the GIF.
**Rejected:** Committing a binary GIF (large, goes stale, unreviewable); fabricating/faking a recording
(dishonest); skipping the demo entirely (loses the portfolio value).
**Status:** Final. Recording + embedding the GIF is a documented user step.

---

### D16 — Canonical project name is `5-DevOps-Toolkit`
**Decision:** The project is named `5-DevOps-Toolkit` everywhere — matching the GitHub remote
(`github.com/www8351/5-DevOps-Toolkit`) and the working directory. All docs, badges, clone URLs, script
headers and the layout tree were aligned to it (the earlier `devops-toolkit-5` spelling is retired).
**Why:** The remote already exists under `5-DevOps-Toolkit`; renaming a live GitHub repo breaks every
existing URL/clone/star and needs a manual GitHub action, whereas the `devops-toolkit-5` name only ever
lived in prose. Aligning docs to the real slug is the lower-risk, reversible-in-docs choice.
**Rejected:** Renaming the GitHub repo to `devops-toolkit-5` (disruptive, breaks links, needs a human on the
GitHub side); leaving the mismatch (broken clone URL and badges — the reason this was flagged in the first
place).
**Note:** Historical `PROGRESS.md` entries that record the original `devops-toolkit-5` intent are left intact
— they document *why* the mismatch existed.
**Status:** Final. If the owner prefers `devops-toolkit-5`, rename the GitHub repo instead and re-align.

---

### D17: Root tools allow a non-root preview under `DRY_RUN=1`
**Decision:** `require_root` returns success for a normal user when `DRY_RUN=1`, after a warning that
this is a preview only. Without `DRY_RUN=1` it still refuses. This only holds because every side effect
in the root tools goes through `run`; any new root tool must keep that rule (D2), and the remaining
hand-rolled write in `install-jenkins.sh` was moved onto `run` for that reason.
**Why:** The README quick start previewed `mkswap.sh` as a normal user and died with "needs root", so the
headline safety feature failed on first contact. The documented workaround, `DRY_RUN=1 sudo ...`, was
worse: `sudo` resets the environment, so the "preview" ran for real.
**Rejected:** Telling users to run `sudo DRY_RUN=1` only (needs root just to read a plan, and the wrong
variable order is an easy, dangerous mistake); dropping the root check from the tools (D2 is final).
**Status:** Final.

---

### D18: paramiko loads known_hosts before trusting a new host
**Decision:** Every paramiko client comes from `utils.ssh_client()`, which calls `load_system_host_keys()`
before `AutoAddPolicy`. A host already in `~/.ssh/known_hosts` must present the same key, or the connection
fails with `BadHostKeyException`. An unknown host is accepted for that session.
**Why:** The fallback used `AutoAddPolicy` with an empty key store, so it accepted any key, including a
changed one: a silent man-in-the-middle hole, and the opposite of what the native tools do. Loading
known_hosts gives the same semantics as OpenSSH `StrictHostKeyChecking=accept-new`, which the native path
already uses (D10).
**Rejected:** `RejectPolicy` (the first password-based `copy_id` to a fresh VM could never succeed, and
that is the fallback's whole job); keeping `AutoAddPolicy` alone (accepts a changed key).
**Status:** Final.

---

### D19: `ec2-deploy.py` follows the same safety contract as the shell tools
**Decision:** A real launch asks y/N first; `--yes` or `ASSUME_YES=1` skips it, a closed stdin means no.
`DRY_RUN=1` maps to `--dry-run` (AWS-side validation, nothing launched). boto3 is imported lazily so `-h`
works without it, and it is listed in `05-docker-devops/requirements.txt`.
**Why:** It was the only tool that can cost money and the only one with no guard, which contradicts D2 for
the one Python tool. The env toggles keep one mental model across all 25 tools.
**Rejected:** A hard cap on `--count` (the prompt already shows the count; a cap is an arbitrary policy);
mocking boto3 to test `launch()` end to end (D12).
**Status:** Final.

---

### D20: ruff gate widened from real-error rules to `E9,F`
**Decision:** CI, the Makefile and `tasks.ps1` run `ruff check --select E9,F` over the Python code and its
tests. Style rules (E/W/I/UP and friends) stay off.
**Why:** D11 promised to tighten once a baseline was clean. The full pyflakes family was 5 findings away
(unused imports and variables), and those findings were real dead code. Pyflakes rules have no style
opinions, so the gate stays a correctness signal.
**Rejected:** A broad ruleset now (142 findings, mostly line length and typing style: noise for this repo).
**Status:** Final; the next step, if ever, is a ruff config file with an explicit ruleset.

---

### D21: Releases are tag-driven, notes come from CHANGELOG.md, the owner pushes the tag
**Decision:** `CHANGELOG.md` (Keep a Changelog, SemVer) is the single source of release notes. Pushing a
`vX.Y.Z` tag runs `.github/workflows/release.yml`, which publishes that version's section as a GitHub
release with the runner's `gh` CLI and fails if the section is missing. The first tag is `v1.0.0`, pushed by
the owner on `main` after this wave merges. Dev tools (`pytest`, `ruff`) and CI actions are pinned, and
Dependabot proposes upgrades.
**Why:** The repo had no versions, so "what changed" lived only in the git log and in these lifecycle files.
A tag plus a curated changelog is what a reader expects from a maintained project, and it keeps the release
a deliberate human step.
**Rejected:** A third-party release action (one more pinned dependency for what `gh release create` does);
auto-tagging from CI (a release should be a decision, not a side effect); generating notes from commit
messages (too granular for readers).
**Status:** Final.

---

### D22: One command-line contract for every tool
**Decision:** Every tool parses its arguments with one `while/case` loop built on `lib/common.sh`:
- `help_requested` makes `-h/--help` work anywhere before `--`; `--` ends the options.
- Every short flag has a long form. A letter means the same thing in every tool: `-n` a row count
  (`--top`, or `--limit`/`--lines` where nothing is ranked), `-f/--file` a file, `-p/--port(s)` a port,
  `-t/--timeout` a timeout, `-s/--size` a size, `-w/--warn` an alert threshold, `-a/--all` "include
  everything", `-u/--user` a user. A meaning used by one tool only gets a long flag only.
- Tools that change the system accept `--dry-run` and `--yes`, the flag forms of `DRY_RUN=1` and
  `ASSUME_YES=1` (a flag also survives `sudo`, which drops environment variables).
- Exit codes: 0 success; 1 a problem found, a failed operation, or a declined prompt; 2 a usage error.
  Usage error = the command line itself is wrong (unknown flag, missing value, malformed number or path,
  wrong argument count). Something wrong in the world (missing file, not root, dependency absent) is 1.
  Report tools (`audit-perms`, `bigfiles`, ...) exit 0 on a completed report; check tools (`diskwatch`,
  `httpcheck`, and in Phase 12 `pingsweep`, `memwatch --warn`) exit 1 when they find a problem.
- Results go to stdout; warnings, errors and the `confirm` question go to stderr.
`tests/bats/help_smoke.bats` enforces the help, exit-2 and executable-bit parts for every tool.
**Why:** The audit found four parser styles, `--help` that only worked as the first argument in seven
tools, one letter with up to five meanings, usage errors indistinguishable from "problem found", and a
declined prompt exiting 0 in six tools and 1 in eight. A toolkit that claims consistency has to be
consistent where a user touches it first: the command line.
**Rejected:** getopts everywhere (no long options, `--help` needs a shim); a full option-parsing library
(a dependency for 25 small scripts); `--opt=value` syntax (more parser code for little gain).
**Note:** `help_requested` scans every argument before `--`, so an option value that is literally `-h` or
`--help` triggers help. Accepted: such values are rare, and the pre-scan is what makes help work even
after an argument the parser would reject. An empty option value counts as missing (`need_arg`).
**Status:** Final.

---

### D23: Renamed flags keep working as deprecated aliases until 2.0.0
**Decision:** When D22 renames a flag, the old spelling keeps its meaning, calls `deprecated OLD NEW` (a
warning on stderr naming the replacement and the removal version), and is listed under "Deprecated" in
the tool's help and in `CHANGELOG.md`. Aliases are removed together in the next major version. Renamed in
1.1.0: `logtop -f/-p`, `diskwatch -t`, `docker-clean -f`, `docker-run-web -n`, `newuser -s/-d/-N`,
`sshkey -c`.
**Why:** The owner's call: existing scripts and muscle memory keep working, and the warning teaches the new
name at the moment it matters. Bundling a clean break with the interface work would have forced 2.0.0
immediately.
**Rejected:** A clean break (version 2.0.0 now); silent aliases (nobody would ever migrate).
**Not covered by aliases (deliberate syntax changes, listed under "Changed" in 1.1.0):** bundled short
options (`-an 5`) and attached values (`-n5`) are no longer parsed, and stray arguments, `0` counts and
leading zeros are usage errors. Supporting bundles generically would need each tool's value-taking
options in a shared pre-parser; the cost outweighed the convenience.
**Status:** Final.

---

### D24: Machine output for the four monitors only; checks exit 1 on a problem
**Decision:** `diskwatch`, `memwatch`, `httpcheck` and `pingsweep` accept `--json` and then print exactly one
JSON document on stdout: a top-level `ok`, the tool's settings, and one record per filesystem, URL or host.
Strings go through `json_str`, numbers through `json_num` (anything else becomes `null`); sizes are KiB
(`df -kP`) or bytes, never human strings. All four exit 1 when they find a problem, including `pingsweep`
(it used to exit 0) and `memwatch` once `-w/--warn` is given. Failing rows go to stdout with healthy ones.
**Why:** These are the tools a cron job, a CI step or another program consumes; the rest are reports for
people. The owner chose this scope. A dependency on `jq` was avoided: the documents are built in Bash and
checked in the tests with Python's json module.
**Rejected:** `--json` on every report tool (much more code for output nobody parses yet); emitting JSON
with `jq -n` (a new runtime dependency); human-readable sizes in JSON (callers would have to parse them).
**Status:** Final; more tools can gain `--json` later under the same document shape.

