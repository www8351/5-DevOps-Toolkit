# 📊 System & Hardware Monitor

One-glance dashboards for host, CPU, memory, disk and swap — small, focused Bash tools built on a shared helper library.
*דשבורדים במבט אחד למארח, מעבד, זיכרון, דיסק ו-swap — כלי Bash ממוקדים על ספריית עזר משותפת.*

## Scripts

| Script | What it does | Key commands | Needs root |
| --- | --- | --- | --- |
| `sysinfo.sh` | Boxed dashboard of host, kernel, CPU, memory and disk | `uname`, `hostnamectl`, `lscpu`, `df`, `free`, `uptime` | No |
| `topproc.sh` | Top-N processes by CPU or memory | `ps`, `sort`, `head` | No |
| `diskwatch.sh` | Flag mounted filesystems above a usage threshold (cron-friendly exit code) | `df`, `awk`, `tr`, `tail` | No |
| `memwatch.sh` | RAM and swap usage report with percentages | `free`, `swapon`, `awk`, `/proc/meminfo` | No |
| `mkswap.sh` | Create and enable a swapfile, optionally persisting in `/etc/fstab` | `fallocate`, `dd`, `chmod`, `mkswap`, `swapon`, `/etc/fstab` | **Yes** |

## Usage

Every script supports `-h` / `--help`:

```bash
./sysinfo.sh -h
```

A few real invocations:

```bash
# Print the full host dashboard
./sysinfo.sh

# Show the 5 hungriest processes by memory
./topproc.sh -m -n 5

# Alert (exit 1) when any real filesystem is at or above 90%
./diskwatch.sh -t 90

# RAM/swap report with percentages
./memwatch.sh

# Create and enable a persistent 2G swapfile (root)
sudo ./mkswap.sh -s 2G --persist
```

## Conventions

- Every script supports `-h` / `--help`.
- Read-only scripts (`sysinfo.sh`, `topproc.sh`, `diskwatch.sh`, `memwatch.sh`) never mutate the system and never require root.
- The destructive script (`mkswap.sh`) requires root, prompts for confirmation, and honours:
  - `DRY_RUN=1` — print the mutating commands instead of executing them.
  - `ASSUME_YES=1` — skip the confirmation prompt (intended for CI).
- Optional tools that are missing are reported via a warning and skipped, rather than crashing the script.
- All scripts source the shared `lib/common.sh` helper library for logging, guards and presentation.
