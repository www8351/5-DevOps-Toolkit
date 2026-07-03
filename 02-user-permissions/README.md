# 👤 Users, Groups & Permissions

Small, focused Bash tools to create users, inspect identities, and audit or repair filesystem ownership and mode bits.
*כלי Bash ממוקדים ליצירת משתמשים, בדיקת זהויות, וביקורת/תיקון בעלות והרשאות קבצים.*

## Scripts

| Script | What it does | Key commands | Needs root |
| --- | --- | --- | --- |
| `newuser.sh` | Create a user with home, login shell and own group, then set a password | `useradd`, `passwd`, `id`, `getent` | Yes |
| `whohas.sh` | Read-only identity report (uid, gid, home, shell, group memberships) | `awk -F:`, `id`, `getent` | No |
| `permfix.sh` | Recursively normalise directory/file modes and ownership (dry-run by default) | `find`, `chmod`, `chown` | Yes (when changing owner) |
| `audit-perms.sh` | Security scan for world-writable, SUID and SGID files | `find -perm`, `awk` | No |
| `grant-sudo.sh` | Add a user to the `sudo`/`wheel` admin group | `usermod -aG`, `getent group`, `id` | Yes |

## Usage

```bash
# See identity details for the current user (read-only)
./whohas.sh
./whohas.sh alice

# Preview a permission repair (dry-run is the default), then apply it
./permfix.sh /srv/www
sudo ./permfix.sh --dirs 750 --files 640 -o www-data:www-data --execute /srv/www

# Scan the system for risky files, capped at 20 results per category
./audit-perms.sh -n 20 /usr

# Create a user, then grant them admin rights
sudo ./newuser.sh -u alice -s /bin/bash
sudo ./grant-sudo.sh -u alice
```

## Conventions

- Every script supports `-h` / `--help`.
- Destructive scripts (`newuser.sh`, `permfix.sh`, `grant-sudo.sh`) honour:
  - `DRY_RUN=1` — print the commands instead of running them.
  - `ASSUME_YES=1` — skip the interactive confirmation prompt.
- `permfix.sh` is **dry-run by default**; pass `--execute` to actually apply changes.
- All scripts source the shared helpers in `../lib/common.sh`.
