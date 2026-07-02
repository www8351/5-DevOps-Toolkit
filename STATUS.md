# STATUS

_Last updated: 2026-07-02_

## Where the project stands
**MVP complete.** A 5-module DevOps shell toolkit (`devops-toolkit-5`) is built, reviewed and pushed to
GitHub as a public repo.

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

## Open / not done
- [ ] Unit tests (e.g. `bats` / `pytest`) — Phase 2 (in progress).
- [ ] Asciinema demo GIFs in the README.
- [ ] `ssh_toolkit` has not been smoke-tested against a live VM (needs a real two-VM lab).

## Next best action
1. Copy `config.example.toml` → `config.toml`, fill in host/user.
2. Run `./setup.sh all --host <IP> --user <USER>` on a Linux VM to verify the full flow.
3. Add `.github/workflows/shellcheck.yml` to enforce the "ShellCheck-clean" badge.

## Blockers / waiting on
None.

## Needs review
**Repo-name mismatch:** GitHub remote is `www8351/5-DevOps-Toolkit`, but README (clone URL, layout tree)
and lifecycle files call the project `devops-toolkit-5`. Badges were fixed to the real slug; the clone URL
and prose still say `devops-toolkit-5`. Decide the canonical name and align.

Destructive/root scripts (`newuser.sh`, `mkswap.sh`, `pkg.sh`, `install-jenkins.sh`, `grant-sudo.sh`) were
verified via `-h` and `DRY_RUN` only — they were **not** executed against a live system. Run them in a
throwaway VM/WSL before relying on them.
