# 🌐 Networking & SSH

Small, focused shell tools to inspect interfaces, sweep hosts, check endpoints and manage SSH keys.
*כלי shell ממוקדים לבדיקת ממשקי רשת, סריקת מארחים, בדיקת endpoints וניהול מפתחות SSH.*

For cross-platform two-VM automation see **[ssh_toolkit](#ssh_toolkit--cross-platform-vm-to-vm-automation)** below.

| Script | What it does | Key commands | Needs root |
| --- | --- | --- | --- |
| `netinfo.sh` | Show interfaces, routes, default gateway and listening ports | `ip addr`, `ip route`, `ss -tlnp`, `netstat` | No |
| `pingsweep.sh` | Ping a list of hosts and print an up/down table | `ping -c1 -W1` | No |
| `httpcheck.sh` | Check HTTP status code and response time for one or more URLs | `curl -o /dev/null -w`, `wget` | No |
| `portscan.sh` | Discover live hosts on a subnet and scan open ports | `nmap -sn`, `nmap -Pn -sV` | No |
| `sshkey.sh` | Generate an ed25519 SSH keypair and optionally copy it to a host | `ssh-keygen -t ed25519`, `ssh-copy-id` | No |
| `name_echo.sh` | Interactive name-echo demo — prompts for a name and prints it N×3 | `read`, `seq` | No |

## Usage

```bash
# Inspect local networking state
./netinfo.sh

# Ping a few hosts, or read them from a file
./pingsweep.sh 1.1.1.1 8.8.8.8 example.com
./pingsweep.sh -f hosts.txt

# Check HTTP endpoints with a 5s timeout
./httpcheck.sh -t 5 https://example.com https://example.org

# Scan ports on a host you are authorised to test
./portscan.sh -p 22,80,443 192.168.1.10
./portscan.sh --discover 192.168.1.0/24

# Generate a key and copy it to a server (Linux / macOS)
./sshkey.sh -C "me@laptop"
./sshkey.sh -c deploy@server.example.com

# Name-echo demo (run 3 iterations instead of the default 2)
./name_echo.sh 3
```

> **Authorization:** `portscan.sh` may only be pointed at hosts you own or have
> explicit written permission to test. Unauthorized scanning can be illegal.

---

## `ssh_toolkit` — Cross-Platform VM-to-VM Automation

A **Python 3.8+ package** that automates the full two-VM SSH lab workflow on **Windows, macOS, and Linux** — no hardcoded usernames or IPs.

Replaces this manual sequence:

```
ip addr → edit /etc/network/interfaces → ifdown/up
ssh-keygen → ssh-copy-id → ssh → scp → remote script
```

with a single command:

```bash
python -m ssh_toolkit all --host 193.168.1.1 --user refael
```

### Quick start

```bash
# Linux / macOS
./setup.sh --help
./setup.sh all --host 193.168.1.1 --user refael

# Windows (PowerShell)
.\setup.ps1 all --host 193.168.1.1 --user refael
```

`setup.sh` / `setup.ps1` create a `.venv`, install `paramiko`, then forward all arguments to the toolkit.

### Subcommands

| Subcommand | What it does |
|------------|--------------|
| `keys` | Generate ed25519 keypair (idempotent — skips if key already exists) |
| `authorize` | Copy public key to remote host — portable `ssh-copy-id` for Windows too |
| `connect` | Test key-based SSH connectivity |
| `transfer` | Push a local file to the remote host via SFTP / `scp` |
| `demo` | Run remote `mkdir`/`touch`/`tar` demo; captures stdout+stderr locally |
| `net` | Configure static IP on local host (default dry-run; requires `--apply`) |
| `all` | Orchestrate all steps: keys → authorize → connect [→ transfer] → demo |

### Configuration (no hardcoding)

Values resolve in order: **CLI flag → `SSHTK_*` env var → `config.toml` → interactive prompt**.

```bash
# Copy the template and fill in your details
cp config.example.toml config.toml   # config.toml is gitignored
```

### Feature flags

| Flag | Effect |
|------|--------|
| `--dry-run` | Print planned actions, touch nothing |
| `--yes` | Auto-confirm all prompts |
| `--verbose` | Show DEBUG output |
| `--apply` | (net / all --with-network) Actually modify the NIC |

### Static IP configuration (`net` subcommand)

**Default: dry-run.** Requires `--apply` to write changes.

Auto-detects the Linux network stack (Netplan → nmcli → `/etc/network/interfaces`).
Creates a **timestamped backup** before touching any file.
After applying, **pings the gateway**; if unreachable within 10s it **auto-rollbacks** to the backup.

```bash
# Preview what would change (safe, no modifications)
python -m ssh_toolkit net --interface enp0s8 --address 193.168.1.2 --gateway 193.168.1.1

# Actually apply (requires root / admin)
sudo python -m ssh_toolkit net --interface enp0s8 --address 193.168.1.2 --gateway 193.168.1.1 --apply
```

### Module layout

```
04-network-ssh/
├── setup.sh / setup.ps1      bootstrappers (create .venv, install deps, forward args)
├── requirements.txt           paramiko>=3.4.0; tomli for Python <3.11
├── config.example.toml        config template (copy to config.toml)
└── ssh_toolkit/
    ├── cli.py                 argparse subcommands + orchestrator
    ├── utils.py               logging, OS detect, config, RollbackStack
    ├── ssh_orchestrator.py    keygen, copy-id, connect test
    ├── payload_executor.py    SFTP transfer + remote demo execution
    └── network_manager.py     OS-aware static IP, backup, rollback
```

---

## Notes

- Every `.sh` script supports `-h` / `--help`.
- `.sh` scripts honour `DRY_RUN=1` and `ASSUME_YES=1`.
- All `.sh` scripts source the shared `lib/common.sh` helper library.
- `ssh_toolkit` uses `--dry-run` / `--yes` flags and has a `--verbose` mode.
