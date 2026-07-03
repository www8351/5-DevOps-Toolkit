# 🗃️ File & Text Plumbing

Small, sharp shell utilities for navigating, inspecting, slicing, and archiving files and text streams.
*כלי shell קטנים וחדים לניווט, בדיקה, חיתוך וארכוב של קבצים וזרימות טקסט.*

All scripts source the shared `lib/common.sh` for coloured logging, safe command execution, and prompts.

## Scripts

| Script | What it does | Key commands | Needs root |
| --- | --- | --- | --- |
| `dirsnap.sh` | Per-subdirectory size snapshot, sorted largest-first, top-N | `du`, `sort`, `head`, `find`, `pwd` | No |
| `logtop.sh` | Top talkers in a log: most frequent value of a chosen field/word | `grep`, `awk`, `sort`, `uniq`, `wc` | No |
| `bigfiles.sh` | The N largest files under a path, with human-readable sizes | `find`, `du`, `sort`, `head` | No |
| `txtstats.sh` | Line/word/char stats plus head & tail preview of a text file | `wc`, `head`, `tail`, `awk` | No |
| `backup.sh` | Timestamped `tar.bz2` backup of a directory, plus an extract mode | `tar`, `du`, `date` | No |

## Usage

Every script prints detailed help with `-h` or `--help`:

```bash
./dirsnap.sh -h
```

Show the 5 biggest subdirectories of `/var`, including hidden ones:

```bash
./dirsnap.sh -n 5 -a /var
```

Find the top client IPs in an access log (field 1, whitespace-delimited):

```bash
./logtop.sh -f 1 -n 20 -p '404' /var/log/nginx/access.log
```

List the 10 largest files over 50 MB under your home directory:

```bash
./bigfiles.sh -n 10 -s +50M "$HOME"
```

Inspect a text file, previewing 8 lines at each end:

```bash
./txtstats.sh -n 8 notes.txt
```

Back up a project, then later extract it:

```bash
./backup.sh ./myproject /tmp/backups
./backup.sh --extract /tmp/backups/myproject-20260627-101500.tar.bz2 ./restore
```

## Conventions

- Every script supports `-h` / `--help`.
- The read-only scripts (`dirsnap.sh`, `logtop.sh`, `bigfiles.sh`, `txtstats.sh`) never modify anything.
- The destructive path in `backup.sh` (extraction) honours `DRY_RUN=1` (print the commands without running them) and `ASSUME_YES=1` (skip confirmation prompts):

```bash
DRY_RUN=1 ./backup.sh --extract archive.tar.bz2 ./restore   # preview only
ASSUME_YES=1 ./backup.sh --extract archive.tar.bz2 ./restore # no prompts
```
