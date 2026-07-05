"""PyInstaller entry shim for the Quorum sidecar (P2.0 bundling spike).

Equivalent to ``python -m services.api``: prints the ``{port, token}`` stdout handshake and runs
uvicorn. Kept as a real script (not ``-m``) because PyInstaller freezes a script entry point.

This is throwaway spike scaffolding — production packaging is P2.6.
"""

from services.api.__main__ import main

if __name__ == "__main__":
    main()
