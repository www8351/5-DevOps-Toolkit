"""
OS-aware static IP configuration with timestamped backup and auto-rollback.

Supported back-ends (auto-detected):
  Linux   — /etc/network/interfaces (Debian legacy)
            /etc/netplan/*.yaml     (Ubuntu 18.04+)
            nmcli                   (NetworkManager / RHEL / Fedora)
  macOS   — networksetup
  Windows — PowerShell New-NetIPAddress / Remove-NetIPAddress

ALL changes default to DRY_RUN unless --apply is passed to the CLI.
After applying, the gateway/peer IP is pinged; consecutive failure triggers
automatic rollback from the timestamped backup.
"""
from __future__ import annotations

import ipaddress
import platform
import re
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

from .utils import RollbackStack, is_linux, is_macos, is_windows, log, ok

# Upper bound for one system command (nmcli, netplan, ifup, PowerShell...).
# A hung command raises TimeoutExpired, which triggers the rollback.
_CMD_TIMEOUT = 60

# Letters, digits, space, dot, colon, underscore and hyphen: enough for Linux
# (enp0s8, eth0.100), macOS (en0, Wi-Fi) and Windows ("Ethernet 2") names,
# while keeping quotes and newlines out of config files and PowerShell.
_IFACE_RE = re.compile(r"[\w .:-]{1,64}")


# ── public entry point ────────────────────────────────────────────────────────

def apply_static_ip(
    interface: str,
    address: str,
    netmask: str,
    gateway: str,
    *,
    apply: bool = False,       # must be True to actually change anything
    rollback: Optional[RollbackStack] = None,
) -> None:
    """
    Configure *interface* with the given static IP.

    Args:
        interface: NIC name, e.g. "enp0s8" (Linux) / "Ethernet" (Win) / "en1" (Mac).
        address:   Static IPv4, e.g. "193.168.1.2".
        netmask:   Subnet mask, e.g. "255.255.255.0".
        gateway:   Peer/gateway IP to ping-validate after apply, e.g. "193.168.1.1".
        apply:     Must be True to write changes. Default False = dry-run only.
        rollback:  External RollbackStack to push undo ops onto. Created internally
                   if not supplied.
    """
    _check_inputs(interface, address, netmask, gateway)
    log.info("Static IP plan: %s → %s / %s  (gateway %s)", interface, address, netmask, gateway)

    if not apply:
        log.warning(
            "[dry-run] No changes made. Re-run with --apply to actually configure the interface."
        )
        _show_plan(interface, address, netmask, gateway)
        return

    rb = rollback or RollbackStack()

    try:
        if is_linux():
            _apply_linux(interface, address, netmask, gateway, rb)
        elif is_macos():
            _apply_macos(interface, address, netmask, rb)
        elif is_windows():
            _apply_windows(interface, address, netmask, rb)
        else:
            raise RuntimeError(f"Unsupported OS: {platform.system()}")

        # Validate: ping gateway / peer
        _validate(gateway, rb)

    except Exception as exc:
        log.error("Network config failed: %s", exc)
        log.warning("Triggering automatic rollback …")
        rb.run()
        raise


# ── input checks ─────────────────────────────────────────────────────────────

def _check_inputs(interface: str, address: str, netmask: str, gateway: str) -> None:
    """Raise ValueError before anything is touched, dry-run included.

    The values end up in /etc/network/interfaces, netplan YAML and PowerShell
    command strings, so they are validated rather than trusted.
    """
    if not _IFACE_RE.fullmatch(interface):
        raise ValueError(f"unsafe or empty interface name: {interface!r}")
    for label, value in (("address", address), ("gateway", gateway)):
        try:
            ipaddress.IPv4Address(value)
        except ValueError:
            raise ValueError(f"invalid {label}: {value!r}") from None
    try:
        if netmask.count(".") != 3:
            raise ValueError
        ipaddress.IPv4Network(f"0.0.0.0/{netmask}")
    except ValueError:
        raise ValueError(f"invalid netmask (want dotted form like 255.255.255.0): {netmask!r}") from None


def _ps_quote(value: str) -> str:
    """Quote *value* as a PowerShell single-quoted string literal."""
    return "'" + value.replace("'", "''") + "'"


# ── plan display ─────────────────────────────────────────────────────────────

def _show_plan(interface: str, address: str, netmask: str, gateway: str) -> None:
    print()
    print("  Would configure:")
    print(f"    Interface : {interface}")
    print(f"    Address   : {address}")
    print(f"    Netmask   : {netmask}")
    print(f"    Gateway   : {gateway}")
    print()


# ── validation ────────────────────────────────────────────────────────────────

def _validate(gateway: str, rb: RollbackStack, timeout: int = 10) -> None:
    """Ping *gateway* for up to *timeout* seconds. Roll back on failure."""
    log.info("Validating connectivity: pinging %s …", gateway)
    deadline = time.monotonic() + timeout
    ping_cmd = (
        ["ping", "-n", "3", "-w", "1000", gateway]  # Windows
        if is_windows()
        else ["ping", "-c", "3", "-W", "1", gateway]
    )

    while time.monotonic() < deadline:
        result = subprocess.run(ping_cmd, capture_output=True, timeout=10)
        if result.returncode == 0:
            ok(f"Connectivity validated: {gateway} is reachable")
            return
        time.sleep(1)

    log.error("Ping to %s failed after %ds — triggering rollback", gateway, timeout)
    rb.run()
    raise RuntimeError(f"Validation failed: {gateway} unreachable after {timeout}s")


# ── Linux back-ends ──────────────────────────────────────────────────────────

def _apply_linux(
    interface: str,
    address: str,
    netmask: str,
    gateway: str,
    rb: RollbackStack,
) -> None:
    """Auto-detect the Linux network stack and delegate."""
    netplan_dir = Path("/etc/netplan")
    interfaces_file = Path("/etc/network/interfaces")

    if netplan_dir.exists() and any(netplan_dir.glob("*.yaml")):
        _apply_netplan(interface, address, netmask, gateway, rb)
    elif shutil.which("nmcli"):
        _apply_nmcli(interface, address, netmask, gateway, rb)
    elif interfaces_file.exists():
        _apply_interfaces(interface, address, netmask, gateway, rb)
    else:
        raise RuntimeError(
            "Cannot detect Linux network stack. "
            "Tried: netplan, nmcli, /etc/network/interfaces."
        )


def _ts_backup(src: Path, rb: RollbackStack) -> Path:
    """Copy *src* to *src.bak.<timestamp>*, push a restore op to *rb*."""
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = src.with_name(src.name + f".bak.{ts}")
    shutil.copy2(src, backup)
    log.info("Backup created: %s", backup)

    original_text = backup.read_text()

    def _restore() -> None:
        src.write_text(original_text)
        log.info("Restored %s from backup", src)

    rb.push(f"restore {src}", _restore)
    return backup


def _apply_interfaces(
    interface: str,
    address: str,
    netmask: str,
    gateway: str,
    rb: RollbackStack,
) -> None:
    iface_file = Path("/etc/network/interfaces")
    _ts_backup(iface_file, rb)

    existing = iface_file.read_text()

    stanza = (
        f"\nauto {interface}\n"
        f"iface {interface} inet static\n"
        f"    address {address}\n"
        f"    netmask {netmask}\n"
        f"    network {_network_addr(address, netmask)}\n"
        f"    broadcast {_broadcast_addr(address, netmask)}\n"
        f"    gateway {gateway}\n"
    )

    # Remove any existing stanza for this interface
    import re
    cleaned = re.sub(
        rf"(auto|allow-hotplug)\s+{re.escape(interface)}.*?(?=\n(auto|allow-hotplug|iface\s+(?!{re.escape(interface)})|$))",
        "",
        existing,
        flags=re.DOTALL,
    )
    iface_file.write_text(cleaned + stanza)

    subprocess.run(["sudo", "ifdown", interface, "--ignore-errors"], check=False, timeout=_CMD_TIMEOUT)
    subprocess.run(["sudo", "ifup", interface], check=True, timeout=_CMD_TIMEOUT)

    ok(f"Static IP applied via /etc/network/interfaces ({interface} = {address})")


def _apply_netplan(
    interface: str,
    address: str,
    netmask: str,
    gateway: str,
    rb: RollbackStack,
) -> None:
    prefix = _mask_to_prefix(netmask)
    yaml_path = Path(f"/etc/netplan/99-ssh-toolkit-{interface}.yaml")

    if yaml_path.exists():
        _ts_backup(yaml_path, rb)

    yaml_content = (
        "network:\n"
        "  version: 2\n"
        "  ethernets:\n"
        f"    {interface}:\n"
        f"      addresses: [{address}/{prefix}]\n"
        f"      routes:\n"
        f"        - to: default\n"
        f"          via: {gateway}\n"
        "      nameservers:\n"
        "        addresses: [8.8.8.8, 8.8.4.4]\n"
        "      dhcp4: false\n"
    )
    yaml_path.write_text(yaml_content)
    rb.push(f"remove {yaml_path}", yaml_path.unlink)

    subprocess.run(["sudo", "netplan", "apply"], check=True, timeout=_CMD_TIMEOUT)
    ok(f"Static IP applied via Netplan ({interface} = {address}/{prefix})")


def _apply_nmcli(
    interface: str,
    address: str,
    netmask: str,
    gateway: str,
    rb: RollbackStack,
) -> None:
    prefix = _mask_to_prefix(netmask)
    conn_name = f"ssh-toolkit-{interface}"

    # Capture current connection for rollback
    result = subprocess.run(
        ["nmcli", "-t", "-f", "NAME,DEVICE", "connection", "show", "--active"],
        capture_output=True,
        text=True,
        timeout=_CMD_TIMEOUT,
    )
    prev_conn = next(
        (line.split(":")[0] for line in result.stdout.splitlines() if f":{interface}" in line),
        None,
    )

    if prev_conn:
        def _restore_conn() -> None:
            subprocess.run(["nmcli", "connection", "delete", conn_name], check=False, timeout=_CMD_TIMEOUT)
            subprocess.run(["nmcli", "connection", "up", prev_conn], check=False, timeout=_CMD_TIMEOUT)
        rb.push(f"nmcli restore {prev_conn}", _restore_conn)

    # Delete previous toolkit connection if it exists
    subprocess.run(["nmcli", "connection", "delete", conn_name], check=False, capture_output=True,
                   timeout=_CMD_TIMEOUT)

    subprocess.run(
        [
            "nmcli", "connection", "add",
            "type", "ethernet",
            "ifname", interface,
            "con-name", conn_name,
            "ip4", f"{address}/{prefix}",
            "gw4", gateway,
        ],
        check=True,
        timeout=_CMD_TIMEOUT,
    )
    subprocess.run(["nmcli", "connection", "up", conn_name], check=True, timeout=_CMD_TIMEOUT)
    ok(f"Static IP applied via nmcli ({interface} = {address}/{prefix})")


# ── macOS back-end ────────────────────────────────────────────────────────────

def _apply_macos(
    interface: str,
    address: str,
    netmask: str,
    rb: RollbackStack,
) -> None:
    def _restore_macos() -> None:
        subprocess.run(
            ["networksetup", "-setdhcp", interface],
            check=False,
            timeout=_CMD_TIMEOUT,
        )
        log.info("macOS: reverted %s to DHCP", interface)

    rb.push(f"macOS revert {interface}", _restore_macos)

    subprocess.run(
        ["networksetup", "-setmanual", interface, address, netmask],
        check=True,
        timeout=_CMD_TIMEOUT,
    )
    ok(f"Static IP applied via networksetup ({interface} = {address})")


# ── Windows back-end ─────────────────────────────────────────────────────────

def _apply_windows(
    interface: str,
    address: str,
    netmask: str,
    rb: RollbackStack,
) -> None:
    prefix = _mask_to_prefix(netmask)
    alias = _ps_quote(interface)

    def _restore_windows() -> None:
        # Re-enable DHCP as the safest rollback on Windows
        subprocess.run(
            ["powershell", "-NonInteractive", "-Command",
             f"Set-NetIPInterface -InterfaceAlias {alias} -Dhcp Enabled; "
             f"ipconfig /renew {alias}"],
            check=False,
            timeout=_CMD_TIMEOUT,
        )
        log.info("Windows: reverted %s to DHCP", interface)

    rb.push(f"Windows revert {interface}", _restore_windows)

    # Remove existing static IP, then add new one
    ps_remove = (
        f"Remove-NetIPAddress -InterfaceAlias {alias} "
        f"-AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue"
    )
    subprocess.run(["powershell", "-NonInteractive", "-Command", ps_remove], check=False,
                   timeout=_CMD_TIMEOUT)

    ps_add = (
        f"New-NetIPAddress -InterfaceAlias {alias} "
        f"-IPAddress {_ps_quote(address)} -PrefixLength {prefix} "
        f"-AddressFamily IPv4"
    )
    subprocess.run(["powershell", "-NonInteractive", "-Command", ps_add], check=True,
                   timeout=_CMD_TIMEOUT)
    ok(f"Static IP applied via PowerShell ({interface} = {address}/{prefix})")


# ── subnet helpers ────────────────────────────────────────────────────────────

def _mask_to_prefix(mask: str) -> int:
    """Convert dotted-decimal mask to CIDR prefix length."""
    return sum(bin(int(octet)).count("1") for octet in mask.split("."))


def _network_addr(ip: str, mask: str) -> str:
    """Compute network address (bitwise AND of IP and mask)."""
    ip_parts = [int(o) for o in ip.split(".")]
    mask_parts = [int(o) for o in mask.split(".")]
    return ".".join(str(a & b) for a, b in zip(ip_parts, mask_parts))


def _broadcast_addr(ip: str, mask: str) -> str:
    """Compute broadcast address."""
    ip_parts = [int(o) for o in ip.split(".")]
    mask_parts = [int(o) for o in mask.split(".")]
    return ".".join(str((a & b) | (~b & 0xFF)) for a, b in zip(ip_parts, mask_parts))
