"""Unit tests for ssh_toolkit.network_manager: input checks and pure helpers.

Pure surface only (D12). subprocess.run is replaced by a tripwire, so a test
fails loudly instead of touching a real interface.
"""
import pytest

from ssh_toolkit import network_manager as nm

GOOD = dict(interface="eth1", address="10.0.0.2", netmask="255.255.255.0", gateway="10.0.0.1")


@pytest.fixture(autouse=True)
def _no_subprocess(monkeypatch):
    def tripwire(*args, **kwargs):
        raise AssertionError(f"subprocess.run called: {args}")
    monkeypatch.setattr(nm.subprocess, "run", tripwire)


# ── subnet helpers ────────────────────────────────────────────────────────────
@pytest.mark.parametrize("mask,prefix", [
    ("255.255.255.0", 24), ("255.255.0.0", 16), ("255.255.255.252", 30), ("0.0.0.0", 0),
])
def test_mask_to_prefix(mask, prefix):
    assert nm._mask_to_prefix(mask) == prefix


def test_network_and_broadcast_addresses():
    assert nm._network_addr("192.168.10.37", "255.255.255.0") == "192.168.10.0"
    assert nm._broadcast_addr("192.168.10.37", "255.255.255.0") == "192.168.10.255"
    assert nm._broadcast_addr("10.1.2.3", "255.255.0.0") == "10.1.255.255"


# ── input validation (runs before any change, dry-run included) ──────────────
def test_valid_plan_dry_run_touches_nothing():
    nm.apply_static_ip(**GOOD, apply=False)


@pytest.mark.parametrize("field,value", [
    ("address", "10.0.0.256"),
    ("address", "not-an-ip"),
    ("gateway", "10.0.0"),
    ("netmask", "255.0.255.0"),      # not contiguous
    ("netmask", "24"),
])
def test_invalid_addresses_are_rejected(field, value):
    with pytest.raises(ValueError):
        nm.apply_static_ip(**{**GOOD, field: value}, apply=False)


@pytest.mark.parametrize("interface", [
    "eth1\nauto eth0",               # would inject a stanza into /etc/network/interfaces
    "eth1'; Remove-Item C:\\x; '",   # would break out of a PowerShell string
    "",
])
def test_unsafe_interface_names_are_rejected(interface):
    with pytest.raises(ValueError):
        nm.apply_static_ip(**{**GOOD, "interface": interface}, apply=False)


@pytest.mark.parametrize("interface", ["enp0s8", "Ethernet 2", "Wi-Fi", "en0", "eth0.100"])
def test_real_interface_names_are_accepted(interface):
    nm.apply_static_ip(**{**GOOD, "interface": interface}, apply=False)


# ── PowerShell quoting ────────────────────────────────────────────────────────
def test_ps_quote_doubles_single_quotes():
    assert nm._ps_quote("Ethernet 2") == "'Ethernet 2'"
    assert nm._ps_quote("it's") == "'it''s'"
