"""Unit tests for ssh_toolkit.utils — pure, VM-free surface only.

No paramiko / no live host: only OS detection, path helpers, RollbackStack,
config loading and the resolve() precedence ladder are exercised.
"""
import logging

import pytest

from ssh_toolkit import utils


# ── OS detection ──────────────────────────────────────────────────────────────
@pytest.mark.parametrize(
    "system,expected",
    [("Linux", "Linux"), ("Darwin", "Darwin"), ("Windows", "Windows")],
)
def test_host_os_passes_through_platform_system(monkeypatch, system, expected):
    monkeypatch.setattr(utils.platform, "system", lambda: system)
    assert utils.host_os() == expected


def test_os_predicates_are_mutually_exclusive(monkeypatch):
    monkeypatch.setattr(utils.platform, "system", lambda: "Linux")
    assert utils.is_linux() and not utils.is_windows() and not utils.is_macos()
    monkeypatch.setattr(utils.platform, "system", lambda: "Windows")
    assert utils.is_windows() and not utils.is_linux() and not utils.is_macos()
    monkeypatch.setattr(utils.platform, "system", lambda: "Darwin")
    assert utils.is_macos() and not utils.is_linux() and not utils.is_windows()


# ── path helpers ──────────────────────────────────────────────────────────────
def test_default_keyfile_is_under_home_ssh(monkeypatch, tmp_path):
    monkeypatch.setattr(utils.Path, "home", classmethod(lambda cls: tmp_path))
    kf = utils.default_keyfile()
    assert kf == tmp_path / ".ssh" / "id_ed25519"


def test_pubkey_path_appends_pub_suffix():
    kf = utils.Path("/home/x/.ssh/id_ed25519")
    assert utils.pubkey_path(kf) == utils.Path("/home/x/.ssh/id_ed25519.pub")


# ── RollbackStack ─────────────────────────────────────────────────────────────
def test_rollback_runs_in_lifo_order_and_clears():
    calls = []
    rb = utils.RollbackStack()
    rb.push("first", lambda: calls.append("first"))
    rb.push("second", lambda: calls.append("second"))
    rb.run()
    assert calls == ["second", "first"]  # LIFO
    # After run() the stack is emptied — a second run is a no-op.
    rb.run()
    assert calls == ["second", "first"]


def test_rollback_continues_after_a_failing_op(caplog):
    calls = []
    rb = utils.RollbackStack()
    rb.push("good-early", lambda: calls.append("good-early"))

    def boom():
        raise RuntimeError("kaboom")

    rb.push("bad", boom)
    rb.push("good-late", lambda: calls.append("good-late"))
    with caplog.at_level(logging.ERROR):
        rb.run()
    # LIFO: good-late runs, bad raises (caught), good-early still runs.
    assert calls == ["good-late", "good-early"]
    assert any("kaboom" in r.getMessage() for r in caplog.records)


# ── config: env + toml ────────────────────────────────────────────────────────
def test_from_env_uses_sshtk_prefix_upper(monkeypatch):
    monkeypatch.setenv("SSHTK_HOST", "1.2.3.4")
    assert utils._from_env("host") == "1.2.3.4"
    assert utils._from_env("missing") == ""


def test_load_toml_flattens_known_sections(tmp_path):
    cfg = tmp_path / "config.toml"
    cfg.write_text(
        '[ssh]\nhost = "10.0.0.5"\nuser = "deploy"\n'
        '[transfer]\nsrc = "/tmp/a"\n'
        '[network]\nip = "10.0.0.5/24"\n'
        "[ignored]\nnope = true\n"
    )
    flat = utils.load_toml(cfg)
    assert flat["host"] == "10.0.0.5"
    assert flat["user"] == "deploy"
    assert flat["src"] == "/tmp/a"
    assert flat["ip"] == "10.0.0.5/24"
    assert "nope" not in flat  # section outside ssh/transfer/network is dropped


def test_load_toml_absent_file_returns_empty(tmp_path):
    assert utils.load_toml(tmp_path / "does-not-exist.toml") == {}


def test_load_toml_returns_empty_when_no_parser(monkeypatch, tmp_path):
    # Even when the file exists, no TOML parser installed → graceful {}.
    cfg = tmp_path / "config.toml"
    cfg.write_text('[ssh]\nhost = "x"\n')
    monkeypatch.setattr(utils, "tomllib", None)
    assert utils.load_toml(cfg) == {}


def test_load_toml_malformed_returns_empty(tmp_path, caplog):
    cfg = tmp_path / "config.toml"
    cfg.write_text("this is = = not valid toml [")
    with caplog.at_level(logging.WARNING):
        assert utils.load_toml(cfg) == {}
    assert any("config.toml" in r.getMessage() for r in caplog.records)


# ── resolve() precedence ladder ───────────────────────────────────────────────
def test_resolve_prefers_arg_over_env_and_toml(monkeypatch):
    monkeypatch.setenv("SSHTK_HOST", "from-env")
    assert utils.resolve("host", "from-arg", {"host": "from-toml"}) == "from-arg"


def test_resolve_falls_back_to_env_when_arg_empty(monkeypatch):
    monkeypatch.setenv("SSHTK_HOST", "from-env")
    assert utils.resolve("host", "", {"host": "from-toml"}) == "from-env"


def test_resolve_falls_back_to_toml_when_arg_and_env_empty(monkeypatch):
    monkeypatch.delenv("SSHTK_HOST", raising=False)
    assert utils.resolve("host", "", {"host": "from-toml"}) == "from-toml"


def test_resolve_returns_empty_when_nothing_and_no_prompt(monkeypatch):
    monkeypatch.delenv("SSHTK_HOST", raising=False)
    assert utils.resolve("host", None, {}) == ""


def test_resolve_prompts_when_all_sources_empty(monkeypatch):
    monkeypatch.delenv("SSHTK_HOST", raising=False)
    monkeypatch.setattr("builtins.input", lambda prompt="": "typed-value")
    assert utils.resolve("host", "", {}, prompt="Host") == "typed-value"


def test_resolve_secret_prompt_uses_getpass(monkeypatch):
    monkeypatch.delenv("SSHTK_PASSWORD", raising=False)
    monkeypatch.setattr(utils.getpass, "getpass", lambda prompt="": "s3cret")
    assert utils.resolve("password", "", {}, prompt="Password", secret=True) == "s3cret"


# ── confirm() ─────────────────────────────────────────────────────────────────
def test_confirm_assume_yes_skips_prompt():
    assert utils.confirm("proceed?", assume_yes=True) is True


@pytest.mark.parametrize(
    "answer,expected",
    [("y", True), ("yes", True), ("Y", True), ("YES", True),
     ("n", False), ("no", False), ("", False), ("garbage", False)],
)
def test_confirm_reads_stdin(monkeypatch, answer, expected):
    monkeypatch.setattr("builtins.input", lambda prompt="": answer)
    assert utils.confirm("proceed?") is expected


# ── ok() logging ──────────────────────────────────────────────────────────────
def test_ok_emits_info_with_message(caplog):
    with caplog.at_level(logging.INFO):
        utils.ok("all good")
    assert any("all good" in r.getMessage() for r in caplog.records)
