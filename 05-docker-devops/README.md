# Docker, Packages & Cloud

Small, focused scripts for wrapping package managers, running and cleaning Docker containers, installing Jenkins, and deploying an EC2 instance.

## Scripts

| Script | What it does | Key commands | Needs root |
| ------ | ------------ | ------------ | ---------- |
| `pkg.sh` | Distro-agnostic package manager wrapper (install/upgrade/remove/update/search) | `apt-get`, `dnf`, `yum` | Yes (mutating subcommands only) |
| `docker-run-web.sh` | Launch a known web image with port/volume mapping, print its URL + IP | `docker run -d -p -v --name`, `docker inspect` | No |
| `docker-clean.sh` | Prune stopped containers and dangling images | `docker ps -a`, `docker rm`, `docker images`, `docker rmi` | No |
| `install-jenkins.sh` | Install Jenkins on Debian/Ubuntu (JDK, repo, service, firewall) | `apt-get`, `curl`, `systemctl`, `ufw` | Yes |
| `ec2-deploy.py` | boto3 mini-deploy: launch a t2.micro EC2 instance from CLI args | `boto3` (`ec2.create_instances`) | No (needs AWS creds) |

## Usage

```bash
# Search for a package (read-only) then install it (root + confirm)
./pkg.sh search nginx
sudo ./pkg.sh install nginx

# Launch nginx on host port 8080 with a custom docroot
./docker-run-web.sh -i nginx -p 8080 -v ./site

# Preview a cleanup without removing anything, then run it for real
DRY_RUN=1 ./docker-clean.sh
./docker-clean.sh

# Install Jenkins on Debian/Ubuntu
sudo ./install-jenkins.sh

# Validate an EC2 launch without actually creating an instance
./ec2-deploy.py --image-id ami-0abcdef1234567890 --dry-run
```

Pass `-h` / `--help` to any script (or `python3 ec2-deploy.py --help`) for full options.

## Notes

- Every script supports `-h` / `--help`.
- Destructive scripts honour `DRY_RUN=1` (print commands instead of running them) and `ASSUME_YES=1` (skip the confirmation prompt).
- The bash scripts source the shared `lib/common.sh` helper library that lives one folder above this directory.
