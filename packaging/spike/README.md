# P2.0 — sidecar-bundling spike

Throwaway spike that proves the Quorum FastAPI sidecar can be PyInstaller-frozen into a standalone
exe and still honour the full desktop contract when launched **outside** the repo `.venv`. The
decision it produces is recorded in [ADR 0002](../../docs/decisions/0002-sidecar-bundling.md).
Production packaging is **P2.6**, not here.

## Contents (tracked)

- `sidecar_entry.py` — PyInstaller script entry (≈ `python -m services.api`).
- `quorum_sidecar_demo.spec` — demo-capable **onedir** spec (excludes the ML engine; relies on the
  `jobs.py` lazy-import refactor).
- `quorum_sidecar_full.spec` — full-engine import-smoke spec (informational; feeds the P2.6 punch-list).
- `spike_check.py` — stdlib-only contract harness (handshake, /healthz, auth, demo SSE, /shutdown,
  parent-PID teardown). Exits 0 iff 11/11 pass.

`build/` and `dist/` are git-ignored.

## Run (from repo root)

```bash
# 1. Pre-freeze gates
.venv/Scripts/python.exe -c "import sys; import services.api.app; assert not [m for m in ('langgraph','yfinance','pandas','numpy','stockstats') if m in sys.modules]"
SPIKE_CWD="$PWD" .venv/Scripts/python.exe packaging/spike/spike_check.py "$PWD/.venv/Scripts/python.exe" -m services.api

# 2. Build demo onedir
.venv/Scripts/pyinstaller.exe packaging/spike/quorum_sidecar_demo.spec \
  --distpath packaging/spike/dist --workpath packaging/spike/build --noconfirm

# 3. Prove it outside the repo/.venv: copy dist/quorum_sidecar elsewhere, then
.venv/Scripts/python.exe packaging/spike/spike_check.py <copied>/quorum_sidecar.exe
```
