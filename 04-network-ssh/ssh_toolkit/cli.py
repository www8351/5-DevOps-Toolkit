"""
cli.py — argument parsing and orchestration for ssh_toolkit.

Subcommands:
  keys        Generate ed25519 keypair (idempotent)
  authorize   Copy public key to remote host (cross-platform ssh-copy-id)
  connect     Test key-based SSH connectivity
  transfer    Push a local file to the remote host via SCP / SFTP
  demo        Run the remote directory / file / archive demo
  net         Configure a static IP on the local host (opt-in, guarded)
  all         Run: keys → authorize → connect [→ transfer] → demo [→ net]

Global flags:
  --host, --user, --port, --keyfile
  --dry-run     Print intended actions without executing anything
  --yes         Skip all y/N confirmation prompts
  --verbose     Show DEBUG output
  --config      Path to config.toml (default: 04-network-ssh/config.toml)
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Optional

from .network_manager import apply_static_ip
from .payload_executor import run_demo, transfer
from .ssh_orchestrator import connect_test, copy_id, ensure_keys
from .utils import default_keyfile, load_toml, log, ok, resolve, setup_logging


# ── helpers ────────────────────────────────────────────────────────────────────

def _need(val: str, name: str) -> str:
    """Abort if *val* is empty — a required value was not supplied."""
    if not val:
        log.error("Missing required value: --%s  (or SSHTK_%s env var or config.toml)", name, name.upper())
        sys.exit(1)
    return val


def _keyfile(args: argparse.Namespace) -> Path:
    raw = getattr(args, "keyfile", None)
    return Path(raw) if raw else default_keyfile()


# ── subcommand handlers ────────────────────────────────────────────────────────

def cmd_keys(args: argparse.Namespace, toml: dict) -> None:
    ensure_keys(
        keyfile=_keyfile(args),
        comment=getattr(args, "comment", ""),
        assume_yes=args.yes,
        dry_run=args.dry_run,
    )


def cmd_authorize(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = int(resolve("port", getattr(args, "port", None), toml) or 22)
    copy_id(
        host=host, user=user, port=port,
        keyfile=_keyfile(args),
        assume_yes=args.yes,
        dry_run=args.dry_run,
    )


def cmd_connect(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = int(resolve("port", getattr(args, "port", None), toml) or 22)
    success = connect_test(
        host=host, user=user, port=port,
        keyfile=_keyfile(args),
        dry_run=args.dry_run,
    )
    if not success:
        sys.exit(1)


def cmd_transfer(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = int(resolve("port", getattr(args, "port", None), toml) or 22)
    src  = _need(resolve("src",  getattr(args, "src",  None), toml, "Local file path"), "src")
    dest = resolve("dest", getattr(args, "dest", None), toml) or "~/"
    transfer(
        src=src, host=host, user=user, dest=dest, port=port,
        keyfile=_keyfile(args),
        dry_run=args.dry_run,
    )


def cmd_demo(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = int(resolve("port", getattr(args, "port", None), toml) or 22)
    remote_dir = getattr(args, "remote_dir", None) or "~/demo_ssh"
    run_demo(
        host=host, user=user, port=port,
        keyfile=_keyfile(args),
        remote_dir=remote_dir,
        dry_run=args.dry_run,
    )


def cmd_net(args: argparse.Namespace, toml: dict) -> None:
    interface = _need(resolve("interface", getattr(args, "interface", None), toml, "Network interface (e.g. enp0s8)"), "interface")
    address   = _need(resolve("address",   getattr(args, "address",   None), toml, "Static IP address"), "address")
    netmask   = resolve("netmask",   getattr(args, "netmask",   None), toml) or "255.255.255.0"
    gateway   = _need(resolve("gateway",   getattr(args, "gateway",   None), toml, "Gateway / peer IP"), "gateway")
    apply_flag = getattr(args, "apply", False)

    apply_static_ip(
        interface=interface,
        address=address,
        netmask=netmask,
        gateway=gateway,
        apply=apply_flag,
    )


def cmd_all(args: argparse.Namespace, toml: dict) -> None:
    """Orchestrate the full VM-to-VM SSH lab flow."""
    # -- Network (optional, guarded) -----------------------------------------
    if getattr(args, "with_network", False):
        log.info("=== Step 0: Network configuration ===")
        cmd_net(args, toml)

    # -- Keys ----------------------------------------------------------------
    log.info("=== Step 1: Generate SSH keys ===")
    cmd_keys(args, toml)

    # -- Authorize -----------------------------------------------------------
    log.info("=== Step 2: Copy public key to remote ===")
    cmd_authorize(args, toml)

    # -- Connect test --------------------------------------------------------
    log.info("=== Step 3: Test SSH connection ===")
    cmd_connect(args, toml)

    # -- Transfer (optional) -------------------------------------------------
    src = resolve("src", getattr(args, "src", None), toml)
    if src:
        log.info("=== Step 4: Transfer file ===")
        cmd_transfer(args, toml)
    else:
        log.info("=== Step 4: Transfer skipped (no --src provided) ===")

    # -- Demo ----------------------------------------------------------------
    log.info("=== Step 5: Remote demo ===")
    cmd_demo(args, toml)

    ok("All steps completed successfully")


# ── argument parser ────────────────────────────────────────────────────────────

def _build_parser() -> argparse.ArgumentParser:
    # Shared SSH flags re-used by most subcommands
    ssh_parent = argparse.ArgumentParser(add_help=False)
    ssh_parent.add_argument("--host",    metavar="HOST",   help="Remote host IP or hostname")
    ssh_parent.add_argument("--user",    metavar="USER",   help="Remote username (default: current user)")
    ssh_parent.add_argument("--port",    metavar="PORT",   type=int, default=22, help="SSH port (default: 22)")
    ssh_parent.add_argument("--keyfile", metavar="PATH",   help="Private key path (default: ~/.ssh/id_ed25519)")

    # Global flags on the root parser
    root = argparse.ArgumentParser(
        prog="ssh_toolkit",
        description="Cross-platform VM-to-VM SSH automation toolkit.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Full lab setup (key → copy → test → demo)\n"
            "  python -m ssh_toolkit all --host 193.168.1.1 --user refael\n\n"
            "  # Just generate keys\n"
            "  python -m ssh_toolkit keys\n\n"
            "  # Push a file\n"
            "  python -m ssh_toolkit transfer --host 193.168.1.1 --user refael "
            "--src ~/Desktop/file.txt --dest ~/Desktop/\n\n"
            "  # Configure static IP (dry-run by default)\n"
            "  python -m ssh_toolkit net --interface enp0s8 --address 193.168.1.2 "
            "--gateway 193.168.1.1\n"
            "  python -m ssh_toolkit net --interface enp0s8 --address 193.168.1.2 "
            "--gateway 193.168.1.1 --apply\n\n"
            "Env vars: SSHTK_HOST, SSHTK_USER, SSHTK_PORT, SSHTK_KEYFILE, "
            "SSHTK_SRC, SSHTK_DEST, SSHTK_INTERFACE, SSHTK_ADDRESS, SSHTK_GATEWAY\n"
        ),
    )
    root.add_argument("--dry-run",  action="store_true", help="Print actions without executing")
    root.add_argument("--yes",      action="store_true", help="Auto-confirm all prompts")
    root.add_argument("--verbose",  action="store_true", help="Show debug output")
    root.add_argument("--config",   metavar="PATH",      help="Path to config.toml")

    sub = root.add_subparsers(dest="cmd", metavar="SUBCOMMAND")
    sub.required = True

    # -- keys ----------------------------------------------------------------
    p_keys = sub.add_parser("keys", parents=[ssh_parent], help="Generate ed25519 keypair")
    p_keys.add_argument("--comment", metavar="TEXT", default="", help="Key comment")

    # -- authorize -----------------------------------------------------------
    sub.add_parser(
        "authorize", parents=[ssh_parent],
        help="Copy public key to remote host (portable ssh-copy-id)",
    )

    # -- connect -------------------------------------------------------------
    sub.add_parser(
        "connect", parents=[ssh_parent],
        help="Test key-based SSH connectivity",
    )

    # -- transfer ------------------------------------------------------------
    p_xfer = sub.add_parser("transfer", parents=[ssh_parent], help="Push a file to the remote host")
    p_xfer.add_argument("--src",  metavar="LOCAL",  help="Local file path")
    p_xfer.add_argument("--dest", metavar="REMOTE", help="Remote destination path")

    # -- demo ----------------------------------------------------------------
    p_demo = sub.add_parser("demo", parents=[ssh_parent], help="Run remote mkdir/touch/tar demo")
    p_demo.add_argument(
        "--remote-dir", dest="remote_dir", metavar="PATH", default="~/demo_ssh",
        help="Remote working directory (default: ~/demo_ssh)",
    )

    # -- net -----------------------------------------------------------------
    p_net = sub.add_parser(
        "net",
        help="Configure static IP (default dry-run; requires --apply + root/admin)",
    )
    p_net.add_argument("--interface", metavar="NIC",  help="Network interface, e.g. enp0s8")
    p_net.add_argument("--address",   metavar="IP",   help="Static IPv4 address")
    p_net.add_argument("--netmask",   metavar="MASK", default="255.255.255.0")
    p_net.add_argument("--gateway",   metavar="IP",   help="Peer / gateway IP for validation ping")
    p_net.add_argument(
        "--apply", action="store_true",
        help="Actually modify the interface (default: dry-run only)",
    )

    # -- all -----------------------------------------------------------------
    p_all = sub.add_parser(
        "all", parents=[ssh_parent],
        help="Full flow: keys → authorize → connect [→ transfer] → demo",
    )
    p_all.add_argument("--src",          metavar="LOCAL",  help="Local file for optional transfer step")
    p_all.add_argument("--dest",         metavar="REMOTE", help="Remote destination for transfer")
    p_all.add_argument("--remote-dir",   dest="remote_dir", metavar="PATH", default="~/demo_ssh")
    p_all.add_argument("--with-network", dest="with_network", action="store_true",
                       help="Also run the 'net' static-IP step (requires --interface, --address, --gateway, --apply)")
    p_all.add_argument("--interface",    metavar="NIC",  help="For --with-network")
    p_all.add_argument("--address",      metavar="IP",   help="For --with-network")
    p_all.add_argument("--netmask",      metavar="MASK", default="255.255.255.0")
    p_all.add_argument("--gateway",      metavar="IP",   help="For --with-network")
    p_all.add_argument("--apply",        action="store_true", help="For --with-network: actually apply")

    return root


# ── entry point ───────────────────────────────────────────────────────────────

def _default_user() -> str:
    import getpass
    return getpass.getuser()


_HANDLERS = {
    "keys":      cmd_keys,
    "authorize": cmd_authorize,
    "connect":   cmd_connect,
    "transfer":  cmd_transfer,
    "demo":      cmd_demo,
    "net":       cmd_net,
    "all":       cmd_all,
}


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.verbose:
        setup_logging(verbose=True)

    # Load config.toml
    config_path = Path(args.config) if getattr(args, "config", None) else None
    toml = load_toml(config_path)

    handler = _HANDLERS.get(args.cmd)
    if not handler:
        parser.print_help()
        sys.exit(1)

    try:
        handler(args, toml)
    except KeyboardInterrupt:
        print()
        log.warning("Interrupted by user")
        sys.exit(130)
    except Exception as exc:
        log.error("%s", exc)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)
