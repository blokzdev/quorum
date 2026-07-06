# Quorum

**A premium desktop research terminal for multi-agent market analysis.** Pick a ticker; a team of
LLM agents — analysts → bull/bear debate → trader → risk team → portfolio manager — argue it out and
produce a **BUY / HOLD / SELL** verdict you can drill into, agent by agent. Models are yours to
choose across many frontier providers, and your API keys never leave your machine.

> **Research / educational tool — not financial advice.** Quorum helps you *think*, it does not tell
> you what to trade. No real-money execution. See the disclaimer below.

> **Status: V1 release hardening (Phase 4) → an unsigned 1.0.0 Windows GA.** The Python engine is
> mature; the Flutter desktop app + FastAPI sidecar shipped through Phases 1–3 (Hub, Model Studio,
> Dream Team per-agent routing, the debate terminal, BYO-key data vendors, historical as-of) and are
> now security- and release-hardened. The first Windows build ships **unsigned** — SmartScreen shows a
> one-time *"More info → Run anyway"* prompt on first launch (production code-signing is a fast-follow;
> see [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md) and *Installing on Windows* below).
> Current phase: [`docs/phase-4-plan.md`](docs/phase-4-plan.md); product vision + signature bets:
> [`docs/roadmap.md`](docs/roadmap.md).

## What it is

Quorum is a de-forked descendant of [**TradingAgents**](https://github.com/TauricResearch/TradingAgents),
evolved into a desktop product: the same LangGraph multi-agent engine as the brain, wrapped in a
frameless 3-pane terminal (pipeline rail / live reasoning feed with a bull-vs-bear tug-of-war /
verdict rail). The engine runs locally as a bundled sidecar, so provider keys stay on the user's
machine — a mobile remote over the same local API is planned post-V1.

### The three signature bets

- **Track Record** — a scorecard of how Quorum's past verdicts actually performed (realized
  hit-rate), so the tool is accountable over time.
- **Dream Team** — assign a different frontier model to each agent role (e.g. Opus for the risk
  debate, a fast model for analysts).
- **A signal layer** — FRED macro + Polymarket probabilities woven into the debate.

## Architecture

- **Engine** (`tradingagents/`, Python + LangGraph) — the brain. `propagate(ticker, date, asset_type)`
  runs the whole graph; `runtime/` adds a TUI-free streaming event seam.
- **Sidecar** (`services/api/`, FastAPI) — a thin local control plane on `127.0.0.1` with a
  per-launch bearer token and an SSE event stream; runs are server-owned durable jobs.
- **Desktop** (`apps/desktop/`, Flutter + `packages/quorum_core/` pure Dart) — the premium UI;
  provider/model selection is backed by the engine's model catalog (Model Studio).

See [`CLAUDE.md`](CLAUDE.md) for a deeper orientation.

## Built on TradingAgents

The multi-agent engine is the open-source [TradingAgents](https://github.com/TauricResearch/TradingAgents)
framework by Tauric Research, used under the **Apache License 2.0**. The `tradingagents/` package is
kept named to preserve merge-ability with upstream. Attribution and the upstream citation are in
[`NOTICE`](NOTICE); the full license is in [`LICENSE`](LICENSE).

## Installing on Windows (first run)

Quorum ships as a per-user Windows installer (`Quorum-Setup-1.0.0.exe`) — **no admin rights needed**.
Early builds are **unsigned** (production code-signing is a fast-follow — [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md)),
so on first download-and-run Windows Defender **SmartScreen** shows a blue *"Windows protected your PC"*
notice. That's expected for a new publisher without established download reputation — not a sign that
anything is wrong. To install:

1. Run `Quorum-Setup-1.0.0.exe`.
2. On the SmartScreen notice, click **More info**.
3. Click **Run anyway**.
4. The per-user install completes with no UAC/admin prompt; launch **Quorum** from the Start menu.

Signed builds (which remove this prompt as reputation builds) land in a 1.x/V2 release.

## Quick start

**Engine + sidecar (Python 3.12):**
```bash
pip install ".[dev]"        # into the repo .venv
pytest                      # CI gate = ruff + pytest
ruff check .
```

**Desktop app (Flutter):**
```bash
cd apps/desktop
flutter test                # Dart unit + golden suite
flutter build windows --debug
```

**Interactive CLI (the original UX reference):**
```bash
tradingagents               # installed command
python -m cli.main          # run from source
```

## Bring your own keys

Quorum is BYO-key: you supply the provider API key for whichever model you pick, and it's sent only
to your local engine at run time (stored in your OS keychain on desktop; never written to disk or
logs). Set the env var for your provider (or enter it in Model Studio):

```bash
export OPENAI_API_KEY=...          # OpenAI (GPT)
export ANTHROPIC_API_KEY=...       # Anthropic (Claude)
export GOOGLE_API_KEY=...          # Google (Gemini)
export XAI_API_KEY=...             # xAI (Grok)
export DEEPSEEK_API_KEY=...        # DeepSeek
export DASHSCOPE_API_KEY=...       # Qwen (International)
export ZHIPU_API_KEY=...           # GLM (Z.AI)
export MINIMAX_API_KEY=...         # MiniMax
export OPENROUTER_API_KEY=...      # OpenRouter
```

Local models need no key: run [Ollama](https://ollama.com) (`llm_provider: "ollama"`, default
`http://localhost:11434/v1`) or any OpenAI-compatible server (vLLM, LM Studio, llama.cpp) via
`llm_provider: "openai_compatible"` + `backend_url`. The full provider list and per-provider notes
are in the engine config (`tradingagents/llm_clients/`).

## Licensing & monetization

Quorum is open source under the **Apache License 2.0** (inherited from, and compatible with, the
TradingAgents engine). The planned model is **open-core**: the local client is and stays open and
free; paid features (cross-device Track Record sync, hosted runs, the maintained signal layer) live
behind a server we operate. See [`docs/monetization.md`](docs/monetization.md) and
[`docs/decisions/0003-open-source-and-open-core-monetization.md`](docs/decisions/0003-open-source-and-open-core-monetization.md).

## Disclaimer

Quorum is a research and educational tool. Its output is generated by language models and is **not
financial, investment, or trading advice**. Markets are risky; LLMs are non-deterministic and can be
confidently wrong. Do your own research and consult a licensed professional before making any
financial decision. Nothing here is a solicitation to buy or sell any security.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

## Citation (upstream engine)

```bibtex
@misc{xiao2025tradingagentsmultiagentsllmfinancial,
      title={TradingAgents: Multi-Agents LLM Financial Trading Framework},
      author={Yijia Xiao and Edward Sun and Di Luo and Wei Wang},
      year={2025},
      eprint={2412.20138},
      archivePrefix={arXiv},
      primaryClass={q-fin.TR},
      url={https://arxiv.org/abs/2412.20138},
}
```
