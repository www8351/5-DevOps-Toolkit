"""SFTP file transfer and remote command execution."""
from __future__ import annotations

import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .utils import default_keyfile, log, ok, remote_exec, ssh_client

# Options for non-interactive native ssh/scp: fail instead of prompting for a
# password, and drop a dead connection after about 45 s of silence.
_SSH_OPTS = [
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=15",
    "-o", "ServerAliveCountMax=3",
]


# ── remote path helpers ───────────────────────────────────────────────────────

def _remote_path(path: str) -> str:
    """Quote *path* for a POSIX remote shell, keeping a leading ~ expandable.

    A quoted ~ is never expanded, so "~/demo" would create a directory that is
    literally named ~. "$HOME" does expand inside double quotes.
    """
    if path == "~":
        return '"$HOME"'
    if path.startswith("~/"):
        return '"$HOME"/' + shlex.quote(path[2:])
    return shlex.quote(path)


def _sftp_path(path: str) -> str:
    """SFTP paths are relative to the login directory and never expand ~."""
    if path in ("~", "~/"):
        return "."
    if path.startswith("~/"):
        return path[2:]
    return path


# ── SFTP / SCP file transfer ──────────────────────────────────────────────────

def transfer(
    src: str,
    host: str,
    user: str,
    dest: str = "~/",
    port: int = 22,
    keyfile: Optional[Path] = None,
    dry_run: bool = False,
) -> None:
    """
    Push *src* (local path) to *user@host:dest* via SFTP (paramiko) or native scp.
    Idempotent: if the remote file already exists with the same name, it is silently
    overwritten (last-write-wins is the expected behaviour for a lab exercise).
    """
    if keyfile is None:
        keyfile = default_keyfile()

    src_path = Path(src)
    if not src_path.exists():
        raise FileNotFoundError(f"Source file not found: {src_path}")

    # Build a clean remote path: if dest ends in '/', append the filename.
    remote_dest = dest.rstrip("/") + "/" + src_path.name if dest.endswith("/") else dest
    target = f"{user}@{host}"
    log.info("Transferring %s → %s:%s (port %d)", src_path, target, remote_dest, port)

    if dry_run:
        log.info("[dry-run] Would scp %s %s:%s", src_path, target, remote_dest)
        return

    # Attempt native scp first (available everywhere modern ssh is installed)
    native_scp = shutil.which("scp")
    if native_scp:
        _scp_native(native_scp, src_path, user, host, port, keyfile, remote_dest)
        ok(f"Transferred {src_path.name} → {target}:{remote_dest}")
        return

    # Paramiko SFTP fallback
    _sftp_paramiko(src_path, user, host, port, keyfile, remote_dest)
    ok(f"Transferred {src_path.name} → {target}:{remote_dest}")


def _scp_native(
    scp: str,
    src: Path,
    user: str,
    host: str,
    port: int,
    keyfile: Path,
    remote_dest: str,
) -> None:
    subprocess.run(
        [
            scp,
            "-P", str(port),
            "-i", str(keyfile),
            *_SSH_OPTS,
            str(src),
            f"{user}@{host}:{remote_dest}",
        ],
        check=True,
        timeout=3600,  # generous cap for a large file; dead links drop sooner
    )


def _sftp_paramiko(
    src: Path,
    user: str,
    host: str,
    port: int,
    keyfile: Path,
    remote_dest: str,
) -> None:
    client = ssh_client("Neither scp nor paramiko is available.")
    client.connect(host, port=port, username=user, key_filename=str(keyfile), timeout=15)
    try:
        # Ensure the remote parent directory exists before the upload starts.
        if "/" in remote_dest:
            parent = remote_dest.rsplit("/", 1)[0] or "/"
            rc, _, err = remote_exec(client, f"mkdir -p {_remote_path(parent)}")
            if rc != 0:
                raise RuntimeError(f"Could not create {parent} on {host}: {err.strip()}")

        sftp = client.open_sftp()
        sftp.put(str(src), _sftp_path(remote_dest))
        sftp.close()
    finally:
        client.close()


# ── remote command execution / demo ──────────────────────────────────────────

def run_remote(
    command: str,
    host: str,
    user: str,
    port: int = 22,
    keyfile: Optional[Path] = None,
    dry_run: bool = False,
    timeout: float = 300,
) -> Tuple[str, str, int]:
    """
    Execute *command* on the remote host.
    Returns (stdout, stderr, exit_status).
    Uses native ssh when available, paramiko otherwise.
    """
    if keyfile is None:
        keyfile = default_keyfile()

    log.info("Remote exec on %s@%s: %s", user, host, command[:80])

    if dry_run:
        log.info("[dry-run] Would run on remote:\n%s", command)
        return ("", "", 0)

    native_ssh = shutil.which("ssh")
    if native_ssh:
        result = subprocess.run(
            [
                native_ssh, "-p", str(port),
                "-i", str(keyfile),
                *_SSH_OPTS,
                f"{user}@{host}", command,
            ],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return (result.stdout, result.stderr, result.returncode)

    client = ssh_client("Neither ssh nor paramiko is available.")
    client.connect(host, port=port, username=user, key_filename=str(keyfile), timeout=15)
    try:
        exit_status, out, err = remote_exec(client, command, timeout=timeout)
        return (out, err, exit_status)
    finally:
        client.close()


def _demo_script(remote_dir: str) -> str:
    """Build the remote demo script for *remote_dir* (a leading ~ expands)."""
    target = _remote_path(remote_dir)
    # Idempotent: mkdir -p ensures re-runs don't fail on existing dir.
    # The tar step overwrites the archive (desired for repeated demo runs).
    return f"""
set -e
mkdir -p {target}
cd {target}
for i in 1 2 3 4 5; do
    touch "$i.txt"
done
tar -zcvf ubuntu_ssh.tgz 1.txt 2.txt 3.txt 4.txt 5.txt
echo "done"
ls -la
""".strip()


def run_demo(
    host: str,
    user: str,
    port: int = 22,
    keyfile: Optional[Path] = None,
    remote_dir: str = "~/demo_ssh",
    dry_run: bool = False,
) -> None:
    """
    Run the original lab demo remotely (idempotent):
      - mkdir -p <remote_dir>/new
      - create 1.txt … 5.txt
      - tar -zcvf ubuntu_ssh.tgz 1.txt 2.txt 3.txt 4.txt 5.txt
      - echo done
      - ls -la

    Captures stdout + stderr and prints them locally for verification.
    """
    if keyfile is None:
        keyfile = default_keyfile()

    demo_script = _demo_script(remote_dir)

    log.info("Running remote demo on %s@%s in %s", user, host, remote_dir)

    stdout, stderr, rc = run_remote(
        demo_script, host, user, port=port, keyfile=keyfile, dry_run=dry_run,
    )

    if dry_run:
        return

    if stdout:
        print("─" * 60)
        print(f"[remote stdout — {user}@{host}:{remote_dir}]")
        print(stdout)
        print("─" * 60)

    if stderr:
        log.warning("Remote stderr:\n%s", stderr)

    if rc != 0:
        raise RuntimeError(f"Remote demo exited with code {rc}")

    ok("Remote demo completed successfully")
