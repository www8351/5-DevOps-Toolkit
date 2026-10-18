"""Unit tests for ec2-deploy.py: arguments, the safety contract, exit codes.

Pure surface only (D12): boto3 is never imported here, launch() is replaced
where a test needs it, and nothing talks to AWS.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "ec2-deploy.py"
AMI = ("--image-id", "ami-0abcdef1234567890")


@pytest.fixture
def ec2(monkeypatch):
    """Load ec2-deploy.py (hyphenated, so not importable by name) with boto3 blocked."""
    monkeypatch.setitem(sys.modules, "boto3", None)
    for var in ("DRY_RUN", "ASSUME_YES"):
        monkeypatch.delenv(var, raising=False)
    spec = importlib.util.spec_from_file_location("ec2_deploy", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_script(*argv):
    """Run the script in a child Python where `import boto3` always fails."""
    code = (
        "import runpy, sys; sys.modules['boto3'] = None; "
        f"sys.argv = ['ec2-deploy.py', *{list(argv)!r}]; "
        f"runpy.run_path({str(SCRIPT)!r}, run_name='__main__')"
    )
    return subprocess.run([sys.executable, "-c", code], capture_output=True, text=True, timeout=30)


# ── help and missing boto3 ────────────────────────────────────────────────────
def test_help_works_without_boto3():
    result = run_script("-h")
    assert result.returncode == 0
    assert "--image-id" in result.stdout


def test_missing_boto3_is_reported_after_parsing():
    result = run_script(*AMI, "--yes")
    assert result.returncode == 1
    assert "boto3 is not installed" in result.stderr


# ── arguments and environment toggles ─────────────────────────────────────────
def test_defaults(ec2):
    args = ec2.parse_args(list(AMI))
    assert (args.instance_type, args.count, args.dry_run, args.yes) == ("t2.micro", 1, False, False)


def test_count_must_be_positive(ec2):
    with pytest.raises(SystemExit) as exc:
        ec2.parse_args([*AMI, "--count", "0"])
    assert exc.value.code == 2


def test_dry_run_env_matches_the_shell_tools(ec2, monkeypatch):
    monkeypatch.setenv("DRY_RUN", "1")
    assert ec2.parse_args(list(AMI)).dry_run is True


def test_assume_yes_env_matches_the_shell_tools(ec2, monkeypatch):
    monkeypatch.setenv("ASSUME_YES", "1")
    assert ec2.parse_args(list(AMI)).yes is True


def test_build_tag_spec(ec2):
    assert ec2.build_tag_spec(None) == []
    assert ec2.build_tag_spec("web-01") == [
        {"ResourceType": "instance", "Tags": [{"Key": "Name", "Value": "web-01"}]}
    ]


# ── confirmation before a real launch ─────────────────────────────────────────
def test_dry_run_never_prompts(ec2, monkeypatch):
    monkeypatch.setattr("builtins.input", lambda _p: pytest.fail("prompted on a dry run"))
    assert ec2.confirm_launch(ec2.parse_args([*AMI, "--dry-run"])) is True


def test_yes_flag_never_prompts(ec2, monkeypatch):
    monkeypatch.setattr("builtins.input", lambda _p: pytest.fail("prompted despite --yes"))
    assert ec2.confirm_launch(ec2.parse_args([*AMI, "--yes"])) is True


@pytest.mark.parametrize("answer,expected", [("y", True), ("YES", True), ("", False), ("n", False)])
def test_real_launch_asks_first(ec2, monkeypatch, answer, expected):
    monkeypatch.setattr("builtins.input", lambda _p: answer)
    assert ec2.confirm_launch(ec2.parse_args(list(AMI))) is expected


def test_closed_stdin_means_no(ec2, monkeypatch):
    def eof(_prompt):
        raise EOFError
    monkeypatch.setattr("builtins.input", eof)
    assert ec2.confirm_launch(ec2.parse_args(list(AMI))) is False


def test_declined_launch_exits_1_without_calling_aws(ec2, monkeypatch):
    monkeypatch.setattr("builtins.input", lambda _p: "n")
    monkeypatch.setattr(ec2, "launch", lambda args: pytest.fail("launch called"))
    assert ec2.main(list(AMI)) == 1


def test_confirmed_launch_returns_launch_exit_code(ec2, monkeypatch):
    monkeypatch.setattr(ec2, "launch", lambda args: 7)
    assert ec2.main([*AMI, "--yes"]) == 7
