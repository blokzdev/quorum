# SETUP.md — Operator & founder setup guide

The **human-side checklist**: what needs an account, key, or a click on *your* end — and, just as
important, what doesn't. For the live action queue see [`HUMAN.md`](HUMAN.md); for the dev build loop see
[`CLAUDE.md`](CLAUDE.md) → *Run / test*. This file is the standing walkthrough behind those.

> **Note on "GA".** Two unrelated meanings collide here: the **1.0.0 GA** = our *General Availability*
> release (§3 below); **GA / GA4** = *Google Analytics*, a product-usage tracker (§4). They're different
> things — §3 is the launch; §4 is an optional, deferred decision.

---

## TL;DR — what actually gates the launch

- **Nothing on the API-key / credentials side blocks shipping.** Quorum is **BYOK + local-first**: the app
  ships with **zero** keys and needs none to run. Each user brings their own LLM key *or* uses free local
  Ollama. You do **not** need to create Firebase / Google / AWS / any cloud account for Quorum to work or
  to ship.
- **The only human-gated steps left for 1.0.0** (all outward-facing, so they're yours, not mine):
  1. **Build the installer** — a one-click CI run (I can stage; §3a).
  2. **(Optional) Microsoft Defender pre-submission** — cuts first-run antivirus false-positives (§3b).
  3. **Publish the release** — tag + GitHub release + distribute. The one act I never self-approve (§3c).
- **Analytics is NOT required for GA** and Firebase can't do Windows desktop anyway — see §4 for the real
  options if you want it later.

---

## 1 · Do I need any API keys or credentials? (No — here's the full map)

| Credential | Who it's for | Required to ship / run? | Cost | Where to get it |
| --- | --- | --- | --- | --- |
| **LLM provider key** (Anthropic / OpenAI / Google / …) | the **end user**, entered in-app | **No** — user-side, BYOK | user pays their own provider | the user's provider console; stored write-only in the OS keychain, injected per-run, **never leaves their machine** |
| **Local Ollama** (free models) | the end user (or you, for free runs) | **No** — the free default path | free | [ollama.com](https://ollama.com) → `ollama pull llama3.2` (tool-capable) |
| **Gemini dev/CI key** (`.env` `GOOGLE_API_KEY`) | **you**, for local dev + CI only | already set — **nothing to do** | free tier | *(dev/CI only — gitignored, never ships, not the product key)* |
| **FRED key** | optional, unlocks macro signals | **No** — optional data vendor | **free** | [fredaccount.stlouisfed.org/apikeys](https://fredaccount.stlouisfed.org/apikeys) |
| **Alpha Vantage key** | optional, alt fundamentals/prices vendor | **No** — yfinance (keyless) is the default | **free** | [alphavantage.co/support/#api-key](https://www.alphavantage.co/support/#api-key) |
| **Firebase / Google Analytics / AWS** | — | **Not used** (see §4) | — | — |

**Bottom line:** the only key *you* might add is a **free FRED and/or Alpha Vantage key** — and only if you
want to exercise those optional data vendors yourself. Everything else is either user-side (BYOK) or already
configured. This is by design: BYOK + local-first is Quorum's core posture.

---

## 2 · Developer setup (build & run locally)

Only needed if you're building/running from source (contributors, or you testing a change).

**Prereqs:** Python 3.12 (repo `.venv`), Flutter 3.38.6 (pinned — matches the byte-exact goldens), VS 2022
C++ toolchain (for the Windows build), Ollama optional (free real runs).

```powershell
pip install ".[dev]"                       # engine + sidecar + dev deps
pytest                                      # engine test suite
ruff check .
cd apps/desktop
flutter test                                # Dart unit + golden suite
flutter run -d windows                      # launch the app (spawns the dev sidecar)
```

The app auto-spawns the Python sidecar; in dev it uses `.venv\Scripts\python.exe -m services.api`, and
when packaged it uses the bundled frozen `quorum_sidecar.exe`. No manual server start needed.

---

## 3 · Shipping the 1.0.0 GA — the founder walkthrough

### 3a · Build the installer

The installer is **release-flavored CI** (`.github/workflows/packaging.yml`), not a per-PR gate. Two ways to
produce `Quorum-Setup-1.0.0.exe`:

- **On demand (recommended for a test artifact):** GitHub → **Actions** → **Packaging** → **Run workflow**
  (leave *sign* off for a real unsigned build) → when it's green, download the **`quorum-installer`**
  artifact from the run's summary page.
- **On the release tag:** pushing the `v1.0.0` tag *automatically* builds + uploads the same artifact (this
  is part of §3c).
- **Locally** (if you prefer): `powershell -File packaging\build_installer.ps1 -Version 1.0.0` →
  `packaging\output\Quorum-Setup-1.0.0.exe`.

The CI build already **self-verifies** end-to-end: freeze regression (every provider SDK imports),
clean-install smoke (install → the frozen sidecar answers `/healthz` → uninstall). So a green run = a
working installer.

### 3b · (Optional) Microsoft Defender pre-submission

**Why:** the sidecar is a PyInstaller `.exe`, a common antivirus false-positive trigger, and we ship
**unsigned** for 1.0.0 (signing is deferred to V2 — [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md)).
Pre-submitting to Microsoft cuts the odds a first-run user sees a Defender flag. Skippable if you accept the
small risk.

**Steps:**
1. Build + install the app once (§3a) so you have both files to submit:
   - the installer: `Quorum-Setup-1.0.0.exe`
   - the frozen sidecar (the real FP risk): `%LOCALAPPDATA%\Programs\Quorum\sidecar\quorum_sidecar.exe`
2. Go to **[microsoft.com/en-us/wdsi/filesubmission](https://www.microsoft.com/en-us/wdsi/filesubmission)**
   and **sign in with your Microsoft account** (lets you track the result).
3. Select **"Software developer"** as the submitter, and **"I believe this file is clean" / false-positive**.
4. Upload **both** `.exe` files. In the notes, give context: *open-source (Apache-2.0) research/education
   desktop app; Flutter UI + a PyInstaller-frozen Python sidecar; public source at
   github.com/blokzdev/quorum; unsigned early release.*
5. Submit. Track status via your MS account. If a launch is ever blocked in production, you can escalate at
   **[msrc.microsoft.com/report](https://msrc.microsoft.com/report)**.

*(Note: changing the binary to "dodge" detection doesn't work — Defender flags behavior; only Microsoft can
clear it. Submission is the correct path, and code-signing in V2 is the durable fix.)*

### 3c · Publish the release *(founder-gated — I stage, you publish)*

When you're ready, I'll stage it one-click:
- draft the **`v1.0.0`** tag + a GitHub Release with notes drawn from `CHANGELOG.md`,
- attach the built installer,
- and hand it to you for the final **Publish** click.

Publishing (tag + release + distribute) is the one outward-facing, irreversible act I **never** self-approve
— so nothing goes public until you say go. The README already documents the first-run **"More info → Run
anyway"** SmartScreen step for unsigned installers, so users have a clear path.

---

## 4 · Analytics — do you need it? (Recommendation: not for GA)

Your question was *"new Firebase project and get GA from Firebase, or GA directly from Google Analytics?"* —
here's the honest picture, because both routes have real problems for **this** app:

- **Firebase Analytics → not an option on Windows.** The `firebase_analytics` Flutter plugin supports only
  **Android / iOS / macOS / web** — **not Windows or Linux desktop**
  ([open FlutterFire issue #12847](https://github.com/firebase/flutterfire/issues/12847)). A new Firebase
  project wouldn't give you analytics on the Windows app.
- **Direct Google Analytics (GA4)** *is* technically possible via the **Measurement Protocol** (send events
  over HTTP; e.g. the [`ambilytics`](https://pub.dev/packages/ambilytics) package wraps GA4 for
  Windows/Linux). But it's **Google telemetry on a product whose whole pitch is local-first / "your keys and
  data never leave your machine."** That's a posture + privacy-disclosure decision, not just plumbing.
- **It's not needed for 1.0.0.** No analytics ships today, and none is required to launch.

**My recommendation:**
1. **Ship 1.0.0 with no analytics** — simplest, and most consistent with the privacy-first posture.
2. **If/when you want product-usage insight**, use **[Aptabase](https://aptabase.com/for-flutter)** rather
   than Firebase/GA: open-source, **privacy-first** (anonymous sessions, *no* device IDs, cookies, or
   fingerprinting), with a real **Windows + Flutter** SDK ([aptabase_flutter](https://github.com/aptabase/aptabase_flutter))
   and a free self-host or generous cloud tier. It matches the "your data stays yours" ethos. Make it
   **opt-in with an in-app disclosure**. ([PostHog](https://posthog.com) is the heavier, more feature-rich
   alternative — session replay, funnels — if you later want deep product analytics over minimal telemetry.)
3. Either way this is a **post-GA (V1.x)** call and a **product/privacy fork** — logged in
   [`HUMAN.md`](HUMAN.md) §2. I won't wire any telemetry until you decide.

---

## 5 · Deferred to V2 — no action now

- **Code-signing certificate** — removes the SmartScreen "Run anyway" warning + builds publisher reputation
  + cuts AV false-positives at the source. Options researched in
  [ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md): **Certum Open Source** (~€29/yr) or **Azure
  Artifact/Trusted Signing** (~$120/yr); free **SignPath Foundation** exists but shows *its* name as the
  publisher and our open-core model risks its eligibility. Revisit when distribution traction warrants; the
  `build_installer.ps1 -Sign` seam is retained so V2 signing is a wiring-only change.
- **Gemini dev-key rotation** — dev/CI hygiene, post-V1. It's gitignored and never ships, so it's not a GA
  gate.

---

## What is *not* blocking the AI work

To be explicit: **no API key, credential, or account setup blocks anything I'm doing.** The remaining Phase-4
work is exactly the two founder-gated, outward-facing actions in §3b/§3c. Everything else — code, tests,
docs, CI, the installer build itself — I can drive to a staged, one-click-for-you state.
