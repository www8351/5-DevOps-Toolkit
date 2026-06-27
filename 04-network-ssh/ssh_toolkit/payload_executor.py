"""SFTP file transfer and remote command execution."""
from __future__ import annotations

import shutil
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .utils import default_keyfile, log, ok


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
            "-o", "StrictHostKeyChecking=accept-new",
            str(src),
            f"{user}@{host}:{remote_dest}",
        ],
        check=True,
    )


def _sftp_paramiko(
    src: Path,
    user: str,
    host: str,
    port: int,
    keyfile: Path,
    remote_dest: str,
) -> None:
    try:
        import paramiko  # type: ignore[import]
    except ImportError:
        raise RuntimeError("Neither scp nor paramiko is available.")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, port=port, username=user, key_filename=str(keyfile), timeout=15)
    try:
        # Ensure remote parent directory exists
        parent = remote_dest.rsplit("/", 1)[0]
        if parent:
            client.exec_command(f'mkdir -p "{parent}"')

        sftp = client.open_sftp()
        sftp.put(str(src), remote_dest)
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
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=10",
                f"{user}@{host}", command,
            ],
            capture_output=True,
            text=True,
        )
        return (result.stdout, result.stderr, result.returncode)

    try:
        import paramiko  # type: ignore[import]
    except ImportError:
        raise RuntimeError("Neither ssh nor paramiko is available.")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, port=port, username=user, key_filename=str(keyfile), timeout=15)
    try:
        _, stdout_fd, stderr_fd = client.exec_command(command)
        exit_status = stdout_fd.channel.recv_exit_status()
        return (stdout_fd.read().decode(), stderr_fd.read().decode(), exit_status)
    finally:
        client.close()


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

    # Idempotent: mkdir -p ensures re-runs don't fail on existing dir.
    # The tar step overwrites the archive (desired for repeated demo runs).
    demo_script = f"""
set -e
mkdir -p "{remote_dir}"
cd "{remote_dir}"
for i in 1 2 3 4 5; do
    touch "$i.txt"
done
tar -zcvf ubuntu_ssh.tgz 1.txt 2.txt 3.txt 4.txt 5.txt
echo "done"
ls -la
""".strip()

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
