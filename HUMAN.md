# HUMAN.md — Co-founder log (ganesh ⇄ Opus 4.8)

> The async standup between the human founder (ganesh) and the AI co-founder/PM (Opus 4.8). Opus
> writes; ganesh reads top-down and acts on §1/§2. This file is a **router + queue, never a source of
> truth** — anything durable lives in an ADR, the plan doc, or `CHANGELOG.md`; here we keep a one-line
> pointer + the human-action delta. If an entry needs more than ~3 lines, it belongs in an ADR and this
> links it. **§1 (blockers) and §2 (forks) are also surfaced in the chat turn** the moment they arise;
> §3/§4/§5 are pull-only. Rules: see CLAUDE.md → *Operating doctrine*.

**Last AI update:** 2026-06-27 (P2.5b)
**Spend this phase:** ~a few cents paid · boundary = **Ollama + demo + the shared Gemini test key only**
(one minimal Gemini cloud validation run, within boundary; no other paid spend without asking).

---

## 1 · ⛔ Blocked on you — *only-human steps; these gate progress*

- **2026-06-27 — Install the VS C++ / CMake desktop toolchain** (admin PowerShell; one-shot, silent):
  ```powershell
  & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe" modify --installPath "C:\Program Files\Microsoft Visual Studio\2022\Community" --add Microsoft.VisualStudio.Workload.NativeDesktop --add Microsoft.VisualStudio.Component.VC.CMake.Project --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.VC.ATL --add Microsoft.VisualStudio.Component.Windows11SDK.22621 --includeRecommended --quiet --norestart
  ```
  Then `flutter doctor -v` should go green. **BLOCKS:** the C3 `flutter build windows --debug` canary,
  live desktop GUI runs, and the P2.6 installer build. Everything to date is verified headlessly +
  by tests/goldens; this only unblocks the *desktop binary* path.

## 2 · 🔱 Want your input — *genuine forks; I have a recommendation*

- _(none open)_

## 3 · ✅ Decisions I made — *FYI; self-approved consequential calls. Newest first; ADR-linked.*

- 2026-06-27 — Locked the **Ultracode operating doctrine** into CLAUDE.md + this file (after an
  adversarial self-pressure-test): fresh-context pre-merge review, artifacts-over-assertions triage,
  the four-check scope wall, the spend/HITL queue. Trimmed the panel's optional CI staleness check
  → `docs/backlog.md` (judged net-new automation, out of scope).
- 2026-06-27 — **Dream Team per-role routing** design: structured `agent_models` map, additive engine
  resolver, capability gate as a Quorum-side catalog `tool_capable` flag → [ADR 0004](docs/decisions/0004-per-agent-model-routing.md).
- 2026-06-27 — Went **public + Apache-2.0 + open-core** (your call); README rewritten Quorum-first,
  NOTICE added → [ADR 0003](docs/decisions/0003-open-source-and-open-core-monetization.md). This
  resolved the GitHub-Actions billing block (public repos get free CI).
- 2026-06-27 — Re-baselined the terminal goldens once to load **MaterialIcons** in the test harness
  (icons were rendering as tofu); icon-only change, read-verified. Folded the sidecar `api` deps into
  the `dev` extra so CI actually tests the sidecar.

## 4 · 📦 What shipped — *per-session digest; skim, not a changelog (CHANGELOG.md is canonical)*

### 2026-06-27 — P2.3 → P2.5b + public/open-core
- **P2.3** Settings & Model Studio (merged), **P2.4** Hub / run history + cached review (merged),
  **P2.5a** engine per-role routing (merged), **P2.5b** agent_models contract + provenance (merged).
- Repo went **public**, Apache-2.0, open-core docs (README/NOTICE/ADR 0003/monetization.md); **CI
  restored + fixed** (sidecar deps).
- Each subphase: workflow research/design + adversarial review (per-finding verified) + headless real
  runs where the synthetic path couldn't prove it. Verified: 59 flutter + 553 pytest + ruff green.

## 5 · 🗄️ Archive — *resolved blocks + decided forks, for traceability*

- ✅ 2026-06-27 — GitHub Actions billing block → resolved by going public (free CI on public repos).
