"""Make the ssh_toolkit package importable when pytest runs from the repo root.

pytest's default (prepend) import mode adds this tests/ dir to sys.path, not its
parent — so `import ssh_toolkit.utils` would fail. Insert 04-network-ssh/ instead.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
