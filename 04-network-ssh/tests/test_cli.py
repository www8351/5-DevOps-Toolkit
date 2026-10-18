"""Unit tests for ssh_toolkit.cli: argument parsing and value precedence.

Pure surface only (D12). The network step is replaced by a recorder, so no
NIC, ssh client or paramiko session is ever touched.
"""
import pytest

from ssh_toolkit import cli

NET_ARGS = ("--interface", "eth1", "--address", "10.0.0.2", "--gateway", "10.0.0.1")


@pytest.fixture(autouse=True)
def _clean_env(monkeypatch):
    """Keep the developer's own SSHTK_* variables out of every test."""
    for key in ("HOST", "USER", "PORT", "KEYFILE", "NETMASK", "REMOTE_DIR"):
        monkeypatch.delenv(f"SSHTK_{key}", raising=False)
    for var in ("DRY_RUN", "ASSUME_YES"):
        monkeypatch.delenv(var, raising=False)


@pytest.fixture
def net_calls(monkeypatch):
    """Record apply_static_ip calls instead of configuring a real interface."""
    calls = []
    monkeypatch.setattr(cli, "apply_static_ip", lambda **kw: calls.append(kw))
    return calls


def parse(*argv):
    return cli._build_parser().parse_args(list(argv))


# ── port precedence: flag > env > config > 22 ────────────────────────────────
def test_port_is_unset_when_flag_absent():
    assert parse("connect").port is None


def test_port_defaults_to_22():
    assert cli._port(parse("connect"), {}) == 22


def test_port_comes_from_config():
    assert cli._port(parse("connect"), {"port": 2200}) == 2200


def test_port_env_beats_config(monkeypatch):
    monkeypatch.setenv("SSHTK_PORT", "2222")
    assert cli._port(parse("connect"), {"port": 2200}) == 2222


def test_port_flag_beats_env_and_config(monkeypatch):
    monkeypatch.setenv("SSHTK_PORT", "2222")
    assert cli._port(parse("connect", "--port", "2022"), {"port": 2200}) == 2022


# ── keyfile precedence: flag > env > config > ~/.ssh/id_ed25519 ──────────────
def test_keyfile_defaults_to_ed25519(monkeypatch, tmp_path):
    monkeypatch.setattr(cli, "default_keyfile", lambda: tmp_path / "id_ed25519")
    assert cli._keyfile(parse("connect"), {}) == tmp_path / "id_ed25519"


def test_keyfile_comes_from_config(tmp_path):
    key = tmp_path / "from_config"
    assert cli._keyfile(parse("connect"), {"keyfile": str(key)}) == key


def test_keyfile_env_beats_config(monkeypatch, tmp_path):
    monkeypatch.setenv("SSHTK_KEYFILE", str(tmp_path / "from_env"))
    got = cli._keyfile(parse("connect"), {"keyfile": str(tmp_path / "from_config")})
    assert got == tmp_path / "from_env"


def test_keyfile_expands_tilde(monkeypatch, tmp_path):
    monkeypatch.setenv("HOME", str(tmp_path))
    monkeypatch.setenv("USERPROFILE", str(tmp_path))
    assert cli._keyfile(parse("connect", "--keyfile", "~/k"), {}) == tmp_path / "k"


# ── global flags work before or after the subcommand ─────────────────────────
def test_global_flags_default_to_false():
    args = parse("connect")
    assert args.dry_run is False and args.yes is False and args.verbose is False


def test_global_flag_before_subcommand_is_kept():
    assert parse("--dry-run", "connect").dry_run is True


def test_global_flag_after_subcommand_is_accepted():
    args = parse("all", "--dry-run", "--yes")
    assert args.dry_run is True and args.yes is True


# ── net: config values, --dry-run beats --apply, confirmation ─────────────────
def test_netmask_is_unset_when_flag_absent():
    assert parse("net").netmask is None


def test_netmask_comes_from_config(net_calls):
    cli.cmd_net(parse("net", *NET_ARGS), {"netmask": "255.255.0.0"})
    assert net_calls[0]["netmask"] == "255.255.0.0"


def test_netmask_defaults_to_slash_24(net_calls):
    cli.cmd_net(parse("net", *NET_ARGS), {})
    assert net_calls[0]["netmask"] == "255.255.255.0"


def test_net_without_apply_is_a_dry_run(net_calls):
    cli.cmd_net(parse("net", *NET_ARGS), {})
    assert net_calls[0]["apply"] is False


@pytest.mark.parametrize("argv", [
    ("--dry-run", "net", *NET_ARGS, "--apply"),
    ("net", *NET_ARGS, "--apply", "--dry-run"),
])
def test_dry_run_overrides_apply(net_calls, argv):
    cli.cmd_net(parse(*argv), {})
    assert net_calls[0]["apply"] is False


def test_apply_asks_before_touching_the_interface(net_calls, monkeypatch):
    monkeypatch.setattr("builtins.input", lambda _prompt: "n")
    with pytest.raises(SystemExit) as exc:
        cli.cmd_net(parse("net", *NET_ARGS, "--apply"), {})
    assert exc.value.code == 1
    assert net_calls == []


def test_apply_runs_after_a_yes_answer(net_calls, monkeypatch):
    monkeypatch.setattr("builtins.input", lambda _prompt: "y")
    cli.cmd_net(parse("net", *NET_ARGS, "--apply"), {})
    assert net_calls[0]["apply"] is True


def test_yes_flag_skips_the_apply_prompt(net_calls, monkeypatch):
    def no_prompt(_prompt):
        raise AssertionError("prompted despite --yes")
    monkeypatch.setattr("builtins.input", no_prompt)
    cli.cmd_net(parse("--yes", "net", *NET_ARGS, "--apply"), {})
    assert net_calls[0]["apply"] is True


# ── shared environment toggles (D22): same names as the shell tools ──────────
@pytest.mark.parametrize("var,attr", [("DRY_RUN", "dry_run"), ("ASSUME_YES", "yes")])
def test_env_toggle_sets_the_flag(monkeypatch, var, attr):
    monkeypatch.setenv(var, "1")
    args = cli._apply_env_toggles(parse("connect"))
    assert getattr(args, attr) is True


@pytest.mark.parametrize("value", ["0", "", "yes"])
def test_env_toggle_only_reacts_to_1(monkeypatch, value):
    monkeypatch.setenv("DRY_RUN", value)
    assert cli._apply_env_toggles(parse("connect")).dry_run is False


def test_dry_run_env_blocks_apply(net_calls, monkeypatch):
    monkeypatch.setenv("DRY_RUN", "1")
    args = cli._apply_env_toggles(parse("net", *NET_ARGS, "--apply"))
    cli.cmd_net(args, {})
    assert net_calls[0]["apply"] is False
