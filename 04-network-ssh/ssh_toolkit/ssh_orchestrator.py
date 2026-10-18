"""SSH key generation, portable copy-id, and connection tests."""
from __future__ import annotations

import getpass
import shlex
import shutil
import socket
import subprocess
from pathlib import Path
from typing import Optional

from .utils import default_keyfile, is_windows, log, ok, pubkey_path, remote_exec, ssh_client


# ── key generation ────────────────────────────────────────────────────────────

def ensure_keys(
    keyfile: Optional[Path] = None,
    comment: str = "",
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
            timeout=60,
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
        # Interactive: the user types the remote password here, so allow time.
        subprocess.run(cmd, check=True, timeout=300)
        ok(f"Public key copied to {target}")
        return

    # Windows fallback: paramiko-based copy to a POSIX remote
    log.info("ssh-copy-id not available — using paramiko (password-based) fallback")
    password = getpass.getpass(f"Password for {target}: ")
    client = ssh_client("paramiko not installed. Run setup.sh / setup.ps1 first.")

    try:
        client.connect(host, port=port, username=user, password=password, timeout=15)

        # $HOME also tells the platforms apart: only a POSIX home starts with "/".
        rc, home, _ = remote_exec(client, 'printf %s "$HOME"')
        home = home.strip()
        if rc != 0 or not home.startswith("/"):
            raise RuntimeError(
                f"{target} does not look like a Linux/macOS host ($HOME={home!r}); "
                "the paramiko fallback only supports POSIX remotes"
            )
        ssh_dir = f"{home}/.ssh"
        auth_keys = f"{ssh_dir}/authorized_keys"

        # Idempotent: skip when the exact key line is already present.
        _, existing, _ = remote_exec(client, f"cat {shlex.quote(auth_keys)} 2>/dev/null || true")
        if pubkey_text in (line.strip() for line in existing.splitlines()):
            log.info("Key already present in %s:%s — Already satisfied", host, auth_keys)
            return

        # The key travels on stdin, never inside the command line.
        rc, _, err = remote_exec(
            client, _append_key_command(ssh_dir, auth_keys), stdin_text=pubkey_text + "\n",
        )
        if rc != 0:
            raise RuntimeError(f"Failed to append key: {err.strip()}")

        ok(f"Public key appended to {host}:{auth_keys}")

    finally:
        client.close()


def _append_key_command(ssh_dir: str, auth_keys: str) -> str:
    """One remote command that creates ~/.ssh and appends stdin to authorized_keys.

    A single command avoids the race of separate exec_command calls, and
    umask 077 means the files are never readable by others, even briefly.
    """
    d, k = shlex.quote(ssh_dir), shlex.quote(auth_keys)
    return f"umask 077 && mkdir -p {d} && chmod 700 {d} && cat >> {k} && chmod 600 {k}"


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
            timeout=30,
        )
        if result.returncode == 0:
            ok(f"SSH connection to {target} successful")
            return True
        log.error("SSH connection failed: %s", result.stderr.decode().strip())
        return False

    # Paramiko fallback
    client = ssh_client("Neither ssh nor paramiko available.")
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
