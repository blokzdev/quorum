# PyInstaller spec — Quorum sidecar, DEMO-capable onedir (P2.0 bundling spike).
#
# Build from the repo root:
#   .venv/Scripts/pyinstaller packaging/spike/quorum_sidecar_demo.spec \
#       --distpath packaging/spike/dist --workpath packaging/spike/build --noconfirm
#
# Relies on the lazy-import refactor (jobs.py defers TradingAgentsGraph): the demo path imports no
# LangGraph/yfinance/pandas/numpy/stockstats, so they are excluded here. langchain_core is NOT
# excluded — it is loaded unconditionally by tradingagents/__init__.py and cannot be dropped without
# editing that package. Throwaway spike; production packaging is P2.6.
import os

_here = SPECPATH
_repo = os.path.abspath(os.path.join(_here, os.pardir, os.pardir))

hiddenimports = [
    # uvicorn.run("services.api.app:app") is a STRING target the analyzer can't follow:
    "services.api.app", "services.api.jobs", "services.api.demo", "services.api.event_log",
    "tradingagents.runtime.events", "tradingagents.runtime.runner", "tradingagents.runtime.isolation",
    "tradingagents.llm_clients.model_catalog", "tradingagents.default_config", "tradingagents.reporting",
    # uvicorn dynamic loaders + the async stack the SSE path needs:
    "uvicorn", "uvicorn.loops.auto", "uvicorn.protocols.http.auto", "uvicorn.lifespan.on",
    "sse_starlette", "anyio", "anyio._backends._asyncio", "sniffio",
    "pydantic", "pydantic_core", "httpx",
]

excludes = [
    "langgraph", "langgraph.checkpoint", "langchain", "langchain_openai", "langchain_anthropic",
    "langchain_google_genai", "yfinance", "pandas", "numpy", "stockstats",
    "anthropic", "openai", "google", "tiktoken", "boto3", "botocore",
]

a = Analysis(
    [os.path.join(_here, "sidecar_entry.py")],
    pathex=[_repo],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=excludes,
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="quorum_sidecar",
    console=True,  # required so the stdout handshake reaches the desktop's piped stdout
    disable_windowed_traceback=False,
)
coll = COLLECT(exe, a.binaries, a.datas, name="quorum_sidecar")
