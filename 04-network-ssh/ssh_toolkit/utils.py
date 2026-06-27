"""Shared utilities: logging, OS detection, config, rollback."""
from __future__ import annotations

import getpass
import logging
import os
import platform
import sys
from pathlib import Path
from typing import Any, Callable, Optional

# Optional TOML support (stdlib 3.11+; pip tomli for 3.8-3.10)
try:
    import tomllib  # type: ignore[import]
except ImportError:
    try:
        import tomli as tomllib  # type: ignore[no-redef,import]
    except ImportError:
        tomllib = None  # type: ignore[assignment]

# ── colour palette ────────────────────────────────────────────────────────────
_TTY = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
_R = "\033[0m"  if _TTY else ""
_G = "\033[32m" if _TTY else ""
_Y = "\033[33m" if _TTY else ""
_E = "\033[31m" if _TTY else ""
_B = "\033[34m" if _TTY else ""


class _ColourFormatter(logging.Formatter):
    _MAP = {
        logging.DEBUG:    (_B, "[i]"),
        logging.INFO:     (_B, "[i]"),
        logging.WARNING:  (_Y, "[!]"),
        logging.ERROR:    (_E, "[✗]"),
        logging.CRITICAL: (_E, "[✗]"),
    }

    def format(self, record: logging.LogRecord) -> str:
        color, tag = self._MAP.get(record.levelno, ("", "[?]"))
        return f"{color}{tag}{_R} {record.getMessage()}"


def setup_logging(verbose: bool = False) -> logging.Logger:
    handler = logging.StreamHandler()
    handler.setFormatter(_ColourFormatter())
    logging.root.handlers.clear()
    logging.root.addHandler(handler)
    logging.root.setLevel(logging.DEBUG if verbose else logging.INFO)
    return logging.getLogger("ssh_toolkit")


log: logging.Logger = setup_logging()


def ok(msg: str) -> None:
    """Green success line."""
    log.info("%s[✓]%s %s", _G, _R, msg)


# ── OS helpers ────────────────────────────────────────────────────────────────
def host_os() -> str:
    """Return 'Linux', 'Darwin', or 'Windows'."""
    return platform.system()


def is_windows() -> bool:
    return platform.system() == "Windows"


def is_macos() -> bool:
    return platform.system() == "Darwin"


def is_linux() -> bool:
    return platform.system() == "Linux"


# ── path helpers ──────────────────────────────────────────────────────────────
def default_keyfile() -> Path:
    return Path.home() / ".ssh" / "id_ed25519"


def pubkey_path(keyfile: Path) -> Path:
    return keyfile.parent / (keyfile.name + ".pub")


# ── RollbackStack ─────────────────────────────────────────────────────────────
class RollbackStack:
    """LIFO stack of undo callables. Call .run() to undo all pushed ops."""

    def __init__(self) -> None:
        self._ops: list[tuple[str, Callable[[], None]]] = []

    def push(self, label: str, fn: Callable[[], None]) -> None:
        self._ops.append((label, fn))

    def run(self) -> None:
        for label, fn in reversed(self._ops):
            try:
                log.warning("Rolling back: %s", label)
                fn()
            except Exception as exc:
                log.error("Rollback '%s' failed: %s", label, exc)
        self._ops.clear()


# ── config loading ─────────────────────────────────────────────────────────────
def _from_env(key: str) -> str:
    return os.environ.get(f"SSHTK_{key.upper()}", "")


def load_toml(config_path: Optional[Path] = None) -> dict[str, Any]:
    """Load config.toml → flat dict. Returns {} if file absent or tomllib unavailable."""
    if config_path is None:
        config_path = Path(__file__).parent.parent / "config.toml"
    if not config_path.exists() or tomllib is None:
        return {}
    try:
        with open(config_path, "rb") as fh:
            raw = tomllib.load(fh)
        flat: dict[str, Any] = {}
        for section in ("ssh", "transfer", "network"):
            flat.update(raw.get(section, {}))
        return flat
    except Exception as exc:
        log.warning("Could not parse config.toml: %s", exc)
        return {}


def resolve(
    key: str,
    arg_val: Any,
    toml: dict[str, Any],
    prompt: Optional[str] = None,
    secret: bool = False,
) -> Any:
    """
    Return first truthy value from: arg_val → SSHTK_<KEY> env → toml → prompt.
    Prompts (with getpass when secret=True) only if all other sources are empty.
    """
    for val in (arg_val, _from_env(key), toml.get(key)):
        if val is not None and val != "":
            return val
    if prompt:
        return getpass.getpass(f"{prompt}: ") if secret else input(f"{prompt}: ").strip()
    return ""


def confirm(question: str, assume_yes: bool = False) -> bool:
    """Return True on y/yes. Skips the prompt when assume_yes is True."""
    if assume_yes:
        log.info("%s", question + " [auto-yes]")
        return True
    ans = input(f"{_Y}[?]{_R} {question} [y/N] ").strip().lower()
    return ans in ("y", "yes")
