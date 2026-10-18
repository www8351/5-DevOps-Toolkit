"""Unit tests for the remote-command helpers in ssh_toolkit.

Pure surface only (D12): command strings, argv lists and the small paramiko
wrappers are checked with in-memory fakes. No ssh process, no paramiko
session, no network.
"""
import shlex
import types

import pytest

from ssh_toolkit import payload_executor as px
from ssh_toolkit import ssh_orchestrator as so
from ssh_toolkit import utils


# ── remote paths: ~ must stay expandable, everything else stays quoted ───────
@pytest.mark.parametrize("path,expected", [
    ("~", '"$HOME"'),
    ("~/demo_ssh", '"$HOME"/demo_ssh'),
    ("~/my dir", "\"$HOME\"/'my dir'"),
    ("/srv/data", "/srv/data"),
    ("/tmp/$(reboot)", "'/tmp/$(reboot)'"),
])
def test_remote_path_quotes_but_keeps_tilde(path, expected):
    assert px._remote_path(path) == expected


@pytest.mark.parametrize("path,expected", [
    ("~", "."),
    ("~/", "."),
    ("~/Desktop/file.txt", "Desktop/file.txt"),
    ("/tmp/file.txt", "/tmp/file.txt"),
])
def test_sftp_path_drops_tilde(path, expected):
    # SFTP paths are relative to the login directory and never expand ~.
    assert px._sftp_path(path) == expected


def test_demo_script_expands_home_instead_of_making_a_tilde_dir():
    script = px._demo_script("~/demo_ssh")
    assert 'mkdir -p "$HOME"/demo_ssh' in script
    assert 'cd "$HOME"/demo_ssh' in script
    assert '"~' not in script


# ── authorized_keys append: one command, key never on the command line ──────
def test_append_key_command_is_one_quoted_command():
    cmd = so._append_key_command("/home/a b/.ssh", "/home/a b/.ssh/authorized_keys")
    tokens = shlex.split(cmd)
    assert "/home/a b/.ssh" in tokens
    assert "/home/a b/.ssh/authorized_keys" in tokens
    assert tokens[:2] == ["umask", "077"]
    assert "cat" in tokens and ">>" in tokens
    assert "echo" not in tokens


# ── native ssh / scp argv ─────────────────────────────────────────────────────
@pytest.fixture
def argv_log(monkeypatch):
    calls = []

    def fake_run(argv, **kwargs):
        calls.append((argv, kwargs))
        return types.SimpleNamespace(returncode=0, stdout="", stderr="")

    monkeypatch.setattr(px.subprocess, "run", fake_run)
    return calls


def test_scp_never_prompts_and_has_a_timeout(argv_log, tmp_path):
    src = tmp_path / "f.txt"
    src.write_text("x")
    px._scp_native("scp", src, "u", "h", 22, tmp_path / "k", "~/f.txt")
    argv, kwargs = argv_log[0]
    assert "BatchMode=yes" in argv
    assert kwargs.get("timeout")


def test_run_remote_never_prompts_and_has_a_timeout(argv_log, monkeypatch, tmp_path):
    monkeypatch.setattr(px.shutil, "which", lambda name: "/usr/bin/" + name)
    px.run_remote("true", "h", "u", keyfile=tmp_path / "k")
    argv, kwargs = argv_log[0]
    assert "BatchMode=yes" in argv
    assert kwargs.get("timeout")


# ── paramiko wrappers, exercised with in-memory fakes ─────────────────────────
def test_ssh_client_loads_known_hosts_before_trusting_new_ones(monkeypatch):
    order = []

    class FakeClient:
        def load_system_host_keys(self):
            order.append("known_hosts")

        def set_missing_host_key_policy(self, policy):
            order.append("policy")

    fake = types.SimpleNamespace(SSHClient=FakeClient, AutoAddPolicy=lambda: object())
    monkeypatch.setitem(__import__("sys").modules, "paramiko", fake)
    utils.ssh_client("paramiko missing")
    assert order == ["known_hosts", "policy"]


def test_ssh_client_explains_a_missing_paramiko(monkeypatch):
    monkeypatch.setitem(__import__("sys").modules, "paramiko", None)
    with pytest.raises(RuntimeError, match="install it"):
        utils.ssh_client("install it")


def test_remote_exec_feeds_stdin_and_waits_for_exit():
    written = []

    class Channel:
        def shutdown_write(self):
            written.append("EOF")

        def recv_exit_status(self):
            return 3

    class Stream:
        def __init__(self, data=b""):
            self.data = data
            self.channel = Channel()

        def write(self, text):
            written.append(text)

        def read(self):
            return self.data

    class FakeClient:
        def exec_command(self, command, timeout=None):
            assert timeout
            return Stream(), Stream(b"out"), Stream(b"err")

    rc, out, err = utils.remote_exec(FakeClient(), "cat", stdin_text="key\n")
    assert (rc, out, err) == (3, "out", "err")
    assert written == ["key\n", "EOF"]
