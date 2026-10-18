# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Pushing a `vX.Y.Z` tag publishes
the matching section below as a GitHub release.

## [Unreleased]

## [1.1.0] - 2026-10-18

One command-line contract for every tool. Nothing is removed: renamed flags
keep working with a warning until 2.0.0.

### Added
- Every flag has a long form, and `-h`/`--help` works anywhere on the line.
- `--dry-run` and `--yes` on every tool that changes the system, as flag forms
  of `DRY_RUN=1` and `ASSUME_YES=1`. Unlike the variables, the flags survive
  `sudo`.
- `--json` for the four monitors (`diskwatch`, `memwatch`, `httpcheck`,
  `pingsweep`): one JSON document on stdout with an `ok` field and one record
  per filesystem, URL or host.
- `memwatch -w/--warn PERCENT`, which exits 1 when RAM use reaches it.
- `ssh_toolkit` honours `DRY_RUN=1` and `ASSUME_YES=1` like the other tools.
- `lib/common.sh`: `usage_error`, `need_arg`, `help_requested`, `deprecated`,
  `confirm_or_abort`, `c_fail`, `json_str`, `json_num`.
- Contract tests that every tool exits 2 on an unknown option and shows help
  when `--help` comes after another argument.

### Changed
- Exit codes are the same everywhere: 0 success, 1 problem found, failed
  operation or declined prompt, 2 usage error. Before, usage errors exited 1.
- Declining a prompt exits 1 in every tool. `backup --extract`, `docker-clean`,
  `docker-run-web`, `install-jenkins`, `pkg` and `sshkey` (copy step) used to
  exit 0.
- `pingsweep` exits 1 when a host is down.
- Failed result rows (`diskwatch`, `httpcheck`, `pingsweep`) go to stdout with
  the healthy ones. Prompts go to stderr.
- Stray arguments are an error (exit 2) in every tool. Before, `backup`,
  `bigfiles`, `dirsnap`, `logtop`, `txtstats`, `audit-perms`, `whohas`,
  `grant-sudo`, `newuser`, `memwatch`, `topproc`, `diskwatch` and
  `docker-run-web` ignored extra arguments, and `permfix` used the last one.
- Counts and timeouts must be plain positive integers: `0` and leading zeros
  (`-n 007`, `httpcheck -t 0`) are usage errors.
- An empty option value (`-o ""`) is a usage error instead of being ignored.
- Bundled short options (`-an 5`) and attached values (`-n5`, `-uBob`) are no
  longer parsed. Pass each flag and its value separately.
- A value that is literally `-h` or `--help` (for example `logtop -g -h`)
  is read as a request for help.

### Deprecated
These still work, print a warning, and will be removed in 2.0.0:
- `logtop -f FIELD`: use `-k`/`--field`.
- `logtop -p PATTERN`: use `-g`/`--grep`.
- `diskwatch -t PERCENT`: use `-w`/`--warn`.
- `docker-clean -f`: use `-a`/`--all`.
- `docker-run-web -n NAME`: use `--name`.
- `newuser -s SHELL`, `-d HOME`, `-N`: use `--shell`, `--home`,
  `--no-user-group`.
- `sshkey -c USER@HOST`: use `--copy-to`.

### Fixed
- `pkg.sh install -h` tried to install a package named `-h`. Other options
  after the subcommand (`--purge`, `--no-install-recommends`) still go to the
  package manager.
- `--` ended the options only in some tools; it now does in all of them.
- `name_echo.sh` treated `--help` and unknown options as the iteration count.
- `sshkey` replacing a key now generates the new pair beside the old one, so a
  failed ssh-keygen leaves the old key in place.
- `sshkey --yes` hung on ssh-keygen's own overwrite prompt when the key
  already existed.
- A dry run of `sshkey` no longer prints "keypair generated".

## [1.0.0] - 2026-10-18

First tagged release.

### Added
- 25 single-purpose tools in five modules (files and text, users and
  permissions, system monitoring, network and SSH, Docker and cloud), all
  built on one shared Bash library, `lib/common.sh`.
- `ssh_toolkit`, a cross-platform Python package for the two-VM SSH lab:
  key generation, a portable `ssh-copy-id`, connection test, file transfer,
  remote demo, and an opt-in static IP step with backup and rollback.
- `ec2-deploy.py`, a boto3 tool that launches EC2 instances from the CLI.
- A common safety contract: `-h` works before any dependency check, and root
  or destructive actions are gated by `require_root`, `confirm`, `DRY_RUN=1`
  and `ASSUME_YES=1`. A normal user can preview a root tool with `DRY_RUN=1`.
- Tests: bats unit tests for `lib/common.sh`, a help and executable-bit
  contract over every tool, behaviour tests for the shell tools on fixtures
  and stubs, and pytest suites for `ssh_toolkit` and `ec2-deploy.py`.
- CI on every push and pull request: shellcheck, `bash -n`, bats, ruff
  (`E9,F`), pytest on Python 3.10 and 3.14, and a Makefile check.
- `make` and `tasks.ps1` task runners with the same targets as CI.
- `CONTRIBUTING.md`, `SECURITY.md`, a read-only demo tour (`docs/demo.sh`),
  Dependabot, and this changelog with a tag-driven release workflow.

### Fixed
- Banners and rules printed invalid UTF-8 in every tool.
- `mkswap.sh`: the help's dry-run example ran for real under `sudo`; a size
  without a unit, or in K, gave different sizes on the fallocate and dd
  paths; huge sizes overflowed; relative paths and dangling symlinks were
  accepted.
- `pkg.sh search` called the nonexistent `apt-get search`; `update` had no
  root check; dnf/yum failures were reported as success.
- `sysinfo.sh` died where `hostnamectl` cannot run (containers, WSL), and
  `lscpu`/`free` parsing broke on localized systems.
- `logtop.sh` exited 141 on large logs and 1 on an empty filter;
  `dirsnap.sh` and `bigfiles.sh` aborted on unreadable directories.
- `diskwatch.sh` alarmed on always-full snap mounts and cut mount points
  that contain spaces; `httpcheck.sh` exited 0 with endpoints down.
- `docker-clean.sh` reported a stopped Docker daemon as "already tidy".
- `ssh_toolkit`: `--dry-run` did not stop `net --apply`; flag defaults hid
  `SSHTK_*` environment and config values; a quoted `~` created a directory
  named `~` on the remote host; the setup scripts only worked from inside
  their own folder.
- Root tools no longer report success during a dry run.

### Security
- The paramiko `copy_id` fallback sends the public key over stdin to a single
  quoted command instead of interpolating it into a remote shell string.
- paramiko loads `~/.ssh/known_hosts` first, so a changed host key is
  rejected.
- Network inputs (interface name, addresses, netmask) are validated, and
  PowerShell arguments are quoted, before anything is configured.
- Every subprocess call has a timeout, and native ssh/scp run with
  `BatchMode=yes`.
- `ec2-deploy.py` asks before a real, billed launch.
- CI actions and dev tools are pinned.

[Unreleased]: https://github.com/www8351/5-DevOps-Toolkit/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/www8351/5-DevOps-Toolkit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/www8351/5-DevOps-Toolkit/releases/tag/v1.0.0
