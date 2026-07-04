# PyInstaller spec — Quorum sidecar, PRODUCTION full-engine freeze (P2.6b).
#
# Promoted from the P2.0 spike (packaging/spike/quorum_sidecar_full.spec), which proved the heavy
# LangChain/LangGraph + dataflows stack freezes and runs a REAL pro run frozen (see ADR 0002). The
# only material change is name="quorum_sidecar" — the exe the installer drops into <appDir>/sidecar/
# and that SidecarLauncher.resolve() spawns. Because jobs.py imports the engine lazily, the engine
# tree is pulled in explicitly via hiddenimports + collect_submodules.
#
# onedir (NOT onefile): onefile re-extracts to a %TEMP%\_MEIxxxx dir per launch, which our
# parent-PID watchdog + taskkill teardown would race (ADR 0002). Build via packaging/build_installer.ps1
# (or directly):
#   .venv/Scripts/python.exe -m PyInstaller packaging/quorum_sidecar.spec \
#       --distpath packaging/dist --workpath packaging/build --noconfirm
import os
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

_here = SPECPATH
_repo = os.path.abspath(os.path.join(_here, os.pardir))

hiddenimports = [
    "services.api.app", "services.api.jobs", "services.api.demo", "services.api.event_log",
    "tradingagents.runtime.events", "tradingagents.runtime.runner", "tradingagents.runtime.isolation",
    "tradingagents.llm_clients.model_catalog", "tradingagents.default_config", "tradingagents.reporting",
    "tradingagents.graph.trading_graph",
    "uvicorn", "uvicorn.loops.auto", "uvicorn.protocols.http.auto", "uvicorn.lifespan.on",
    "sse_starlette", "anyio", "anyio._backends._asyncio", "sniffio",
    "pydantic", "pydantic_core", "httpx",
    "langgraph", "langgraph.checkpoint.sqlite", "langgraph.pregel",
    "langchain_core.runnables", "langchain_core.output_parsers",
]
hiddenimports += collect_submodules("langchain_core")
hiddenimports += collect_submodules("langgraph")

datas = collect_data_files("tiktoken")

a = Analysis(
    [os.path.join(_here, "sidecar_entry.py")],
    pathex=[_repo],
    binaries=[],
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="quorum_sidecar",
    console=True,
)
coll = COLLECT(exe, a.binaries, a.datas, name="quorum_sidecar")
