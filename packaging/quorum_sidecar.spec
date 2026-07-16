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
from PyInstaller.utils.hooks import collect_submodules, collect_data_files, collect_all

_here = SPECPATH
_repo = os.path.abspath(os.path.join(_here, os.pardir))

hiddenimports = [
    "services.api.app", "services.api.jobs", "services.api.demo", "services.api.event_log",
    "tradingagents.runtime.events", "tradingagents.runtime.runner", "tradingagents.runtime.isolation",
    "tradingagents.llm_clients.model_catalog", "tradingagents.llm_clients.edge_catalog",
    "tradingagents.default_config", "tradingagents.reporting",
    "tradingagents.graph.trading_graph",
    # Provider client stack — factory.create_llm_client imports these LAZILY (inside function bodies),
    # so PyInstaller's static analysis never follows them. Without forcing them + their heavy provider
    # SDKs below, a real (non-demo) run crashes at client construction with ModuleNotFoundError — the
    # demo path never calls create_llm_client, so this is invisible to the demo contract check.
    "tradingagents.llm_clients.factory",
    "tradingagents.llm_clients.openai_client",   # openai + all OpenAI-compatible (ollama, xai, deepseek…)
    "tradingagents.llm_clients.anthropic_client",
    "tradingagents.llm_clients.google_client",
    "tradingagents.llm_clients.azure_client",     # AzureChatOpenAI (rides langchain_openai)
    # NOTE: bedrock_client is intentionally NOT forced — its langchain_aws/boto3 deps aren't in the
    # repo env, so Bedrock is unsupported in the frozen build until those are added (tracked: backlog).
    "uvicorn", "uvicorn.loops.auto", "uvicorn.protocols.http.auto", "uvicorn.lifespan.on",
    "sse_starlette", "anyio", "anyio._backends._asyncio", "sniffio",
    "pydantic", "pydantic_core", "httpx",
    "langgraph", "langgraph.checkpoint.sqlite", "langgraph.pregel",
    "langchain_core.runnables", "langchain_core.output_parsers",
]
hiddenimports += collect_submodules("langchain_core")
hiddenimports += collect_submodules("langgraph")

datas = collect_data_files("tiktoken")
binaries = []
# The provider LLM SDKs + LangChain wrappers. collect_all (submodules + data + binaries) because these
# packages carry data files (tokenizers, version metadata) and dynamically import subpackages the
# static graph misses (anthropic.lib.*, openai.resources.*, google.genai._gaos.*).
for _pkg in ("langchain_openai", "langchain_anthropic", "langchain_google_genai",
             "anthropic", "openai", "google.genai"):
    _d, _b, _h = collect_all(_pkg)
    datas += _d
    binaries += _b
    hiddenimports += _h

a = Analysis(
    [os.path.join(_here, "sidecar_entry.py")],
    pathex=[_repo],
    binaries=binaries,
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
