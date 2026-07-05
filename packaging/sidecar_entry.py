"""PyInstaller entry shim for the Quorum sidecar (production, P2.6).

Equivalent to ``python -m services.api``: prints the ``{port, token}`` stdout handshake and runs
uvicorn. Kept as a real script (not ``-m``) because PyInstaller freezes a script entry point.

The frozen exe is named ``quorum_sidecar.exe`` and is bundled by the installer into
``<appDir>/sidecar/`` — where ``DesktopSidecarEndpoint`` / ``SidecarLauncher.resolve()`` looks for it.
"""

from services.api.__main__ import main

if __name__ == "__main__":
    main()
