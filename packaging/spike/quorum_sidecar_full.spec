# PyInstaller spec — Quorum sidecar, FULL-ENGINE import smoke (P2.0 spike; informational, non-gating).
#
# Proves a frozen build can `import tradingagents.graph.trading_graph.TradingAgentsGraph` and reach
# /healthz — i.e. that the heavy LangChain/LangGraph stack freezes at all. Failures here are NOT a
# P2.0 gate; they populate the P2.6 (installer) punch-list. Because jobs.py now imports the engine
# lazily, the engine is pulled in explicitly via hiddenimports + collect_submodules.
#
# Build from repo root (time-box this — collect_submodules on langchain is large):
#   .venv/Scripts/python.exe -m PyInstaller packaging/spike/quorum_sidecar_full.spec \
#       --distpath packaging/spike/dist-full --workpath packaging/spike/build-full --noconfirm
import os
from PyInstaller.utils.hooks import collect_submodules, collect_data_files

_here = SPECPATH
_repo = os.path.abspath(os.path.join(_here, os.pardir, os.pardir))

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
    name="quorum_sidecar_full",
    console=True,
)
coll = COLLECT(exe, a.binaries, a.datas, name="quorum_sidecar_full")
