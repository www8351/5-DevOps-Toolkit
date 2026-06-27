# Networking & SSH

Small, focused shell tools to inspect interfaces, sweep hosts, check endpoints and manage SSH keys.

| Script | What it does | Key commands | Needs root |
| --- | --- | --- | --- |
| `netinfo.sh` | Show interfaces, routes, default gateway and listening ports | `ip addr`, `ip route`, `ss -tlnp`, `netstat` | No |
| `pingsweep.sh` | Ping a list of hosts and print an up/down table | `ping -c1 -W1` | No |
| `httpcheck.sh` | Check HTTP status code and response time for one or more URLs | `curl -o /dev/null -w`, `wget` | No |
| `portscan.sh` | Discover live hosts on a subnet and scan open ports | `nmap -sn`, `nmap -Pn -sV` | No |
| `sshkey.sh` | Generate an ed25519 SSH keypair and optionally copy it to a host | `ssh-keygen -t ed25519`, `ssh-copy-id` | No |

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

# Generate a key and copy it to a server
./sshkey.sh -C "me@laptop"
./sshkey.sh -c deploy@server.example.com
```

> **Authorization:** `portscan.sh` may only be pointed at hosts you own or have
> explicit written permission to test. Unauthorized scanning can be illegal.

## Notes

- Every script supports `-h` / `--help`.
- State-changing scripts honour `DRY_RUN=1` (print commands instead of running them)
  and `ASSUME_YES=1` (auto-confirm prompts). For example: `DRY_RUN=1 ./sshkey.sh`.
- All scripts source the shared `lib/common.sh` helper library.
