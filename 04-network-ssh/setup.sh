#!/usr/bin/env bash
# setup.sh — bootstrap ssh_toolkit on Linux / macOS
#
# Creates a Python venv, installs dependencies, then forwards all arguments
# to the toolkit:
#   ./setup.sh --help
#   ./setup.sh all --host 193.168.1.1 --user refael
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
REQ="${SCRIPT_DIR}/requirements.txt"

# ── find Python 3 ─────────────────────────────────────────────────────────────
PY=""
for candidate in python3 python python3.12 python3.11 python3.10 python3.9 python3.8; do
  if command -v "$candidate" >/dev/null 2>&1; then
    if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
      PY="$candidate"
      break
    fi
  fi
done

if [[ -z "$PY" ]]; then
  echo "[✗] Python 3.8+ not found. Install it from https://python.org and retry." >&2
  exit 1
fi

echo "[i] Using: $($PY --version)"

# ── create venv ───────────────────────────────────────────────────────────────
if [[ ! -d "$VENV_DIR" ]]; then
  echo "[i] Creating virtual environment at .venv …"
  "$PY" -m venv "$VENV_DIR"
fi

VENV_PY="${VENV_DIR}/bin/python"

# ── install dependencies ───────────────────────────────────────────────────────
echo "[i] Installing dependencies …"
"$VENV_PY" -m pip install --quiet --upgrade pip
"$VENV_PY" -m pip install --quiet -r "$REQ"

echo "[✓] Environment ready."

# ── copy example config if config.toml is missing ─────────────────────────────
if [[ ! -f "${SCRIPT_DIR}/config.toml" && -f "${SCRIPT_DIR}/config.example.toml" ]]; then
  cp "${SCRIPT_DIR}/config.example.toml" "${SCRIPT_DIR}/config.toml"
  echo "[!] config.toml created from example — edit it before running."
fi

# ── launch toolkit ────────────────────────────────────────────────────────────
exec "$VENV_PY" -m ssh_toolkit "$@"
