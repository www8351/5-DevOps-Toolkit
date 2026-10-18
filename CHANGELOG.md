# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/). Pushing a `vX.Y.Z` tag publishes
the matching section below as a GitHub release.

## [Unreleased]

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

[Unreleased]: https://github.com/www8351/5-DevOps-Toolkit/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/www8351/5-DevOps-Toolkit/releases/tag/v1.0.0
