"""Launch the Quorum API sidecar: bind 127.0.0.1 on an ephemeral port with a per-launch token.

On start it prints a single JSON handshake line to stdout for the GUI to parse::

    {"quorum_api": true, "host": "127.0.0.1", "port": 51234, "token": "…", "contract_version": 1}

Set ``QUORUM_PARENT_PID`` so the sidecar self-exits if the GUI dies (no orphaned engine holding the
port). ``QUORUM_API_PORT`` / ``QUORUM_API_TOKEN`` pin those values for tests / scripted runs.
"""

from __future__ import annotations

import json
import os
import secrets
import socket
import threading
import time

import uvicorn


def _free_port() -> int:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]
    finally:
        s.close()


_STILL_ACTIVE = 259  # GetExitCodeProcess code for a process that has not exited


def _pid_alive(pid: int) -> bool:
    try:
        if os.name == "nt":
            import ctypes

            kernel32 = ctypes.windll.kernel32
            kernel32.OpenProcess.restype = ctypes.c_void_p  # avoid 64-bit handle truncation
            handle = kernel32.OpenProcess(0x1000, False, pid)  # PROCESS_QUERY_LIMITED_INFORMATION
            if not handle:
                return False
            try:
                # OpenProcess hands back a live handle even for an already-exited PID, so confirm
                # liveness via the exit code: only STILL_ACTIVE (259) means the process is running.
                exit_code = ctypes.c_ulong()
                ok = kernel32.GetExitCodeProcess(ctypes.c_void_p(handle), ctypes.byref(exit_code))
                if not ok:
                    return False
                return exit_code.value == _STILL_ACTIVE
            finally:
                kernel32.CloseHandle(ctypes.c_void_p(handle))
        os.kill(pid, 0)
        return True
    except (OSError, ValueError):
        return False


def _watch_parent(pid: int) -> None:
    while True:
        time.sleep(2)
        if not _pid_alive(pid):
            os._exit(0)


def main() -> None:
    token = os.environ.get("QUORUM_API_TOKEN") or secrets.token_urlsafe(32)
    os.environ["QUORUM_API_TOKEN"] = token
    port = int(os.environ.get("QUORUM_API_PORT") or _free_port())

    parent = os.environ.get("QUORUM_PARENT_PID")
    if parent and parent.isdigit():
        threading.Thread(target=_watch_parent, args=(int(parent),), daemon=True).start()

    print(json.dumps({
        "quorum_api": True, "host": "127.0.0.1", "port": port,
        "token": token, "contract_version": 1,
    }), flush=True)

    uvicorn.run("services.api.app:app", host="127.0.0.1", port=port, log_level="warning")


if __name__ == "__main__":
    main()
