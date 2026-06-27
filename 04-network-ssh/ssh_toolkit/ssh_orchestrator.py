"""SSH key generation, portable copy-id, and connection tests."""
from __future__ import annotations

import getpass
import shutil
import socket
import subprocess
import sys
from pathlib import Path
from typing import Optional

from .utils import confirm, default_keyfile, is_windows, log, ok, pubkey_path


# ── key generation ────────────────────────────────────────────────────────────

def ensure_keys(
    keyfile: Optional[Path] = None,
    comment: str = "",
    assume_yes: bool = False,
    dry_run: bool = False,
) -> Path:
    """
    Generate an ed25519 keypair at *keyfile* if it does not already exist (idempotent).
    Returns the private key path.
    """
    if keyfile is None:
        keyfile = default_keyfile()

    if keyfile.exists():
        log.info("Keys already exist at %s — skipping generation (Already satisfied)", keyfile)
        return keyfile

    if not comment:
        user = getpass.getuser()
        host = socket.gethostname()
        comment = f"{user}@{host}"

    log.info("Generating ed25519 keypair: %s", keyfile)
    log.info("Comment: %s", comment)

    if dry_run:
        log.info("[dry-run] ssh-keygen -t ed25519 -f %s -C %s -N ''", keyfile, comment)
        return keyfile

    # Ensure ~/.ssh exists with correct permissions
    ssh_dir = keyfile.parent
    if not ssh_dir.exists():
        ssh_dir.mkdir(mode=0o700, parents=True)
        log.info("Created directory: %s", ssh_dir)
    if not is_windows():
        ssh_dir.chmod(0o700)

    try:
        subprocess.run(
            ["ssh-keygen", "-t", "ed25519", "-f", str(keyfile), "-C", comment, "-N", ""],
            check=True,
        )
    except FileNotFoundError:
        log.info("ssh-keygen not found — using paramiko to generate key")
        _keygen_paramiko(keyfile, comment)

    ok(f"Keypair generated: {keyfile}  (+ {keyfile}.pub)")
    return keyfile


def _keygen_paramiko(keyfile: Path, comment: str) -> None:
    """Fallback key generation using paramiko when ssh-keygen is unavailable."""
    try:
        from paramiko import Ed25519Key  # type: ignore[import]
    except ImportError:
        raise RuntimeError(
            "Neither ssh-keygen nor paramiko is available. "
            "Run setup.sh / setup.ps1 to install dependencies."
        )
    key = Ed25519Key.generate()
    key.write_private_key_file(str(keyfile))
    pub_path = pubkey_path(keyfile)
    pub_path.write_text(f"{key.get_name()} {key.get_base64()} {comment}\n")
    if not is_windows():
        keyfile.chmod(0o600)
        pub_path.chmod(0o644)


# ── portable ssh-copy-id ──────────────────────────────────────────────────────

def copy_id(
    host: str,
    user: str,
    port: int = 22,
    keyfile: Optional[Path] = None,
    assume_yes: bool = False,
    dry_run: bool = False,
) -> None:
    """
    Cross-platform equivalent of ssh-copy-id.

    Tries native ssh-copy-id first (Linux/macOS). Falls back to a paramiko
    password-authenticated session that appends the pubkey to authorized_keys.
    Idempotent: skips if the key is already present.
    """
    if keyfile is None:
        keyfile = default_keyfile()

    pub = pubkey_path(keyfile)
    if not pub.exists():
        raise FileNotFoundError(f"Public key not found: {pub}")

    pubkey_text = pub.read_text().strip()
    target = f"{user}@{host}"

    log.info("Copying public key to %s (port %d)", target, port)

    if dry_run:
        log.info("[dry-run] Would append %s to %s:.ssh/authorized_keys", pub, target)
        return

    # Fast path: native ssh-copy-id (Linux / macOS)
    native = shutil.which("ssh-copy-id")
    if native:
        cmd = [native, "-i", str(pub), "-p", str(port), target]
        log.info("Using native ssh-copy-id")
        subprocess.run(cmd, check=True)
        ok(f"Public key copied to {target}")
        return

    # Windows fallback: paramiko-based copy
    log.info("ssh-copy-id not available — using paramiko (password-based) fallback")
    password = getpass.getpass(f"Password for {target}: ")

    try:
        import paramiko  # type: ignore[import]
    except ImportError:
        raise RuntimeError(
            "paramiko not installed. Run setup.sh / setup.ps1 first."
        )

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    log.warning(
        "Host key verification disabled for initial key copy. "
        "Remove AutoAddPolicy after first connect for security."
    )

    try:
        client.connect(host, port=port, username=user, password=password, timeout=15)

        # Detect remote home directory
        _, stdout, _ = client.exec_command('echo "$HOME"')
        remote_home = stdout.read().decode().strip()
        if not remote_home or remote_home == "$HOME":
            # Windows remote or $HOME not set
            _, stdout, _ = client.exec_command("echo %USERPROFILE%")
            remote_home = stdout.read().decode().strip()
        if not remote_home:
            remote_home = f"/home/{user}" if user != "root" else "/root"

        remote_ssh_dir = f"{remote_home}/.ssh"
        auth_keys_path = f"{remote_ssh_dir}/authorized_keys"

        # Detect remote OS (POSIX vs Windows)
        _, stdout, _ = client.exec_command("uname 2>/dev/null; echo $?")
        uname_out = stdout.read().decode().strip()
        is_posix_remote = not uname_out.startswith("0") and bool(uname_out)

        # Create ~/.ssh directory
        client.exec_command(f'mkdir -p "{remote_ssh_dir}"')
        if is_posix_remote:
            client.exec_command(f'chmod 700 "{remote_ssh_dir}"')

        # Check if key already present (idempotent)
        _, stdout, _ = client.exec_command(f'cat "{auth_keys_path}" 2>/dev/null || echo ""')
        existing_keys = stdout.read().decode()
        if pubkey_text in existing_keys:
            log.info("Key already present in %s:%s — Already satisfied", host, auth_keys_path)
            return

        # Append key
        _, stdout, stderr = client.exec_command(
            f'echo "{pubkey_text}" >> "{auth_keys_path}"'
        )
        exit_status = stdout.channel.recv_exit_status()
        if exit_status != 0:
            err = stderr.read().decode()
            raise RuntimeError(f"Failed to append key: {err}")

        if is_posix_remote:
            client.exec_command(f'chmod 600 "{auth_keys_path}"')

        ok(f"Public key appended to {host}:{auth_keys_path}")

    finally:
        client.close()


# ── connection test ────────────────────────────────────────────────────────────

def connect_test(
    host: str,
    user: str,
    port: int = 22,
    keyfile: Optional[Path] = None,
    dry_run: bool = False,
) -> bool:
    """
    Test key-based SSH connectivity. Returns True on success.
    Tries the native ssh client first; falls back to paramiko.
    """
    if keyfile is None:
        keyfile = default_keyfile()

    target = f"{user}@{host}"
    log.info("Testing SSH connection to %s (port %d, key %s)", target, port, keyfile)

    if dry_run:
        log.info("[dry-run] Would run: ssh -p %d -i %s %s true", port, keyfile, target)
        return True

    native_ssh = shutil.which("ssh")
    if native_ssh:
        result = subprocess.run(
            [
                native_ssh, "-p", str(port),
                "-i", str(keyfile),
                "-o", "StrictHostKeyChecking=accept-new",
                "-o", "ConnectTimeout=10",
                "-o", "BatchMode=yes",
                target, "true",
            ],
            capture_output=True,
        )
        if result.returncode == 0:
            ok(f"SSH connection to {target} successful")
            return True
        log.error("SSH connection failed: %s", result.stderr.decode().strip())
        return False

    # Paramiko fallback
    try:
        import paramiko  # type: ignore[import]
    except ImportError:
        raise RuntimeError("Neither ssh nor paramiko available.")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(
            host, port=port, username=user,
            key_filename=str(keyfile), timeout=10,
        )
        client.close()
        ok(f"SSH connection to {target} successful")
        return True
    except Exception as exc:
        log.error("SSH connection failed: %s", exc)
        return False
