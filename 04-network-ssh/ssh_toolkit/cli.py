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

Global flags (accepted before or after the subcommand):
  --dry-run     Print intended actions without executing anything
  --yes         Skip the y/N confirmation before `net --apply`
  --verbose     Show DEBUG output
  --config      Path to config.toml (default: 04-network-ssh/config.toml)

SSH flags: --host, --user, --port, --keyfile
Precedence for every value: CLI flag > SSHTK_* env var > config.toml > default.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .network_manager import apply_static_ip
from .payload_executor import run_demo, transfer
from .ssh_orchestrator import connect_test, copy_id, ensure_keys
from .utils import confirm, default_keyfile, load_toml, log, ok, resolve, setup_logging


# ── helpers ────────────────────────────────────────────────────────────────────

def _need(val: str, name: str) -> str:
    """Abort if *val* is empty — a required value was not supplied."""
    if not val:
        log.error("Missing required value: --%s  (or SSHTK_%s env var or config.toml)", name, name.upper())
        sys.exit(1)
    return val


def _keyfile(args: argparse.Namespace, toml: dict) -> Path:
    raw = resolve("keyfile", getattr(args, "keyfile", None), toml)
    return Path(raw).expanduser() if raw else default_keyfile()


def _port(args: argparse.Namespace, toml: dict) -> int:
    return int(resolve("port", getattr(args, "port", None), toml) or 22)


# ── subcommand handlers ────────────────────────────────────────────────────────

def cmd_keys(args: argparse.Namespace, toml: dict) -> None:
    ensure_keys(
        keyfile=_keyfile(args, toml),
        comment=getattr(args, "comment", ""),
        dry_run=args.dry_run,
    )


def cmd_authorize(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = _port(args, toml)
    copy_id(
        host=host, user=user, port=port,
        keyfile=_keyfile(args, toml),
        dry_run=args.dry_run,
    )


def cmd_connect(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = _port(args, toml)
    success = connect_test(
        host=host, user=user, port=port,
        keyfile=_keyfile(args, toml),
        dry_run=args.dry_run,
    )
    if not success:
        sys.exit(1)


def cmd_transfer(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = _port(args, toml)
    src  = _need(resolve("src",  getattr(args, "src",  None), toml, "Local file path"), "src")
    dest = resolve("dest", getattr(args, "dest", None), toml) or "~/"
    transfer(
        src=src, host=host, user=user, dest=dest, port=port,
        keyfile=_keyfile(args, toml),
        dry_run=args.dry_run,
    )


def cmd_demo(args: argparse.Namespace, toml: dict) -> None:
    host = _need(resolve("host", getattr(args, "host", None), toml, "Remote host"), "host")
    user = resolve("user", getattr(args, "user", None), toml, "Remote user") or _default_user()
    port = _port(args, toml)
    remote_dir = resolve("remote_dir", getattr(args, "remote_dir", None), toml) or "~/demo_ssh"
    run_demo(
        host=host, user=user, port=port,
        keyfile=_keyfile(args, toml),
        remote_dir=remote_dir,
        dry_run=args.dry_run,
    )


def cmd_net(args: argparse.Namespace, toml: dict) -> None:
    interface = _need(resolve("interface", getattr(args, "interface", None), toml, "Network interface (e.g. enp0s8)"), "interface")
    address   = _need(resolve("address",   getattr(args, "address",   None), toml, "Static IP address"), "address")
    netmask   = resolve("netmask",   getattr(args, "netmask",   None), toml) or "255.255.255.0"
    gateway   = _need(resolve("gateway",   getattr(args, "gateway",   None), toml, "Gateway / peer IP"), "gateway")

    # D9: nothing touches a NIC without --apply, and --dry-run always wins.
    apply_flag = getattr(args, "apply", False)
    if apply_flag and args.dry_run:
        log.warning("--dry-run overrides --apply: the interface will not be changed")
        apply_flag = False
    if apply_flag and not confirm(
        f"Apply static IP {address}/{netmask} to {interface}? "
        "A wrong value can cut off remote access.",
        assume_yes=args.yes,
    ):
        log.error("Aborted: interface left unchanged")
        sys.exit(1)

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

def _add_global_flags(parser: argparse.ArgumentParser, suppress: bool) -> None:
    """Add --dry-run/--yes/--verbose/--config to *parser*.

    The root parser owns the real defaults. Subcommands get SUPPRESS, so a
    flag given before the subcommand is not reset by the subcommand's default.
    """
    flag_default = argparse.SUPPRESS if suppress else False
    path_default = argparse.SUPPRESS if suppress else None
    parser.add_argument("--dry-run", action="store_true", default=flag_default,
                        help="Print actions without executing")
    parser.add_argument("--yes",     action="store_true", default=flag_default,
                        help="Skip the confirmation before net --apply")
    parser.add_argument("--verbose", action="store_true", default=flag_default,
                        help="Show debug output")
    parser.add_argument("--config",  metavar="PATH", default=path_default,
                        help="Path to config.toml")


def _build_parser() -> argparse.ArgumentParser:
    global_parent = argparse.ArgumentParser(add_help=False)
    _add_global_flags(global_parent, suppress=True)

    # Shared SSH flags re-used by most subcommands
    ssh_parent = argparse.ArgumentParser(add_help=False, parents=[global_parent])
    ssh_parent.add_argument("--host",    metavar="HOST",   help="Remote host IP or hostname")
    ssh_parent.add_argument("--user",    metavar="USER",   help="Remote username (default: current user)")
    ssh_parent.add_argument("--port",    metavar="PORT",   type=int, help="SSH port (default: 22)")
    ssh_parent.add_argument("--keyfile", metavar="PATH",   help="Private key path (default: ~/.ssh/id_ed25519)")

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
    _add_global_flags(root, suppress=False)

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
        "--remote-dir", dest="remote_dir", metavar="PATH",
        help="Remote working directory (default: ~/demo_ssh)",
    )

    # -- net -----------------------------------------------------------------
    p_net = sub.add_parser(
        "net", parents=[global_parent],
        help="Configure static IP (default dry-run; requires --apply + root/admin)",
    )
    p_net.add_argument("--interface", metavar="NIC",  help="Network interface, e.g. enp0s8")
    p_net.add_argument("--address",   metavar="IP",   help="Static IPv4 address")
    p_net.add_argument("--netmask",   metavar="MASK", help="Subnet mask (default: 255.255.255.0)")
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
    p_all.add_argument("--remote-dir",   dest="remote_dir", metavar="PATH")
    p_all.add_argument("--with-network", dest="with_network", action="store_true",
                       help="Also run the 'net' static-IP step (requires --interface, --address, --gateway, --apply)")
    p_all.add_argument("--interface",    metavar="NIC",  help="For --with-network")
    p_all.add_argument("--address",      metavar="IP",   help="For --with-network")
    p_all.add_argument("--netmask",      metavar="MASK", help="For --with-network")
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
