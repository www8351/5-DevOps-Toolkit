# Security policy

## Supported versions

Only the latest release gets fixes. Older tags are not patched.

## Reporting a vulnerability

Please report security problems privately through GitHub: open the
repository's **Security** tab and choose **Report a vulnerability**. Do not
open a public issue for a security problem. Reports are handled on a best
effort basis, usually within a week.

Useful details: the tool and version, the exact command, the platform, and
what happened compared with what you expected.

## Using the tools safely

- Several tools change the system and need root: `newuser.sh`,
  `grant-sudo.sh`, `mkswap.sh`, `pkg.sh` (install, upgrade, remove, update)
  and `install-jenkins.sh`. Preview them first with `DRY_RUN=1`, which works
  without root and changes nothing. With `sudo`, put the variable after it:
  `sudo DRY_RUN=1 ./tool.sh`, because `sudo` drops variables set before it.
- `permfix.sh` is a dry run unless `--execute` is given, and it refuses `/`.
- `ssh_toolkit net` only changes a network interface with `--apply`, asks
  before doing so, and `--dry-run` always wins. A wrong address can cut off a
  remote session, so try it on a VM with console access.
- `ssh_toolkit` trusts an unknown host key on first use and rejects a key
  that differs from `~/.ssh/known_hosts`, like OpenSSH `accept-new`. Check
  the fingerprint out of band when that matters.
- `ec2-deploy.py` launches billed AWS resources. It asks before a real
  launch; use `--dry-run` to validate a request first.
- Never commit `04-network-ssh/config.toml`, keys or AWS credentials. The
  `.gitignore` blocks the usual names.
