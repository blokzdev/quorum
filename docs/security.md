# Security model & threat model

> How Quorum protects your credentials and your machine. For **reporting** a vulnerability, see
> [`SECURITY.md`](../SECURITY.md). This document is the architecture-level threat model: assets, trust
> boundaries, the controls in place (with code references), and the residual risks we knowingly accept.
> It is grounded in the code as of Phase 4; keep it current when the sidecar/keystore/isolation changes.

Quorum is a **local-first desktop research terminal**. The Flutter desktop app spawns a bundled Python
FastAPI **sidecar** as a child process and talks to it over loopback HTTP. Provider API keys are
**bring-your-own (BYO)**: entered in the UI, stored in the OS keychain, injected into the sidecar
per-run, and **never persisted to disk in plaintext**.

> Quorum is a research/educational tool, **not financial advice**, and executes **no real-money
> trades**. The posture below concerns credential + process safety, not trading risk.

## Assets

| Asset | Sensitivity | Where it lives |
|---|---|---|
| BYO provider/vendor API keys | **High** | OS keychain at rest (`quorum_apikey_<provider>`, `apps/desktop/lib/services/key_vault.dart`); the run request body in transit; `os.environ` + in-memory `Job.request` for the duration of a run |
| Per-launch bearer token | **High** | Generated at sidecar boot (`services/api/__main__.py`); handed to the GUI on the stdout handshake; sent as an `Authorization` header |
| Raw `.env` keys (host import source) | **High** | The host's gitignored `.env`; surfaced by the host-only `/env-keys` import endpoint |
| Run reports / manifests | Low–Medium | `<results_dir>/quorum_runs/` (report tree, `reports.json`, `run.json`) |

## Trust boundaries

1. **Local process → sidecar (loopback).** The sidecar binds `127.0.0.1` on an **ephemeral port**
   (`services/api/__main__.py`) — no off-host access is possible. Every route except `/healthz`
   requires a **per-launch bearer token** (`services/api/app.py` `_bearer_auth`; `_PUBLIC_PATHS =
   {"/healthz"}`). The token is `secrets.token_urlsafe(32)`, fresh each launch.
2. **GUI → sidecar child (spawn).** The port + token secret is delivered on the child's **private
   stdout pipe** as a single JSON handshake line — never as a command-line argument (which would be
   visible in the process table) and never in a file. Only `QUORUM_PARENT_PID` is passed into the
   child's environment.
3. **Keys at rest → keys in use.** Keys move from the OS-encrypted keychain into the run request and
   then into the engine's process environment **only for the duration of a run**, and are
   popped/restored on exit (`tradingagents/runtime/isolation.py` `JobIsolationContext`; the cleanup
   path returns `False`, so an exception mid-run never bypasses it). Run manifests serialize an
   explicit **allowlist** of non-secret fields — `api_keys` and the raw request are never written.
4. **Public GitHub repo → developer tree.** The repo is public + Apache-2.0. `.env*` and other secret
   files are gitignored, CI runs with a read-only token, and a **secret-scan gate** (`gitleaks`) fails
   the build on any committed credential.
5. **Sidecar → third-party provider APIs.** The user's keys + prompts egress over HTTPS to the chosen
   LLM/data providers under the BYO model; local (Ollama) runs keep everything on-device — no key, no
   egress.

## The localhost-sidecar model

- **Bind:** `127.0.0.1:0` — loopback only, OS-assigned ephemeral port.
- **Auth:** per-launch bearer token (`secrets.token_urlsafe(32)`), required on all routes but
  `/healthz`, sent as an `Authorization: Bearer` header (never in a URL, so never in an access log;
  uvicorn access logging is additionally suppressed at `log_level=warning`).
- **Lifecycle watchdog:** the GUI passes `QUORUM_PARENT_PID`; the sidecar self-exits within ~2s of the
  parent dying (`_pid_alive` confirms liveness via `GetExitCodeProcess == STILL_ACTIVE` to avoid a
  PID-reuse false positive). Teardown is `/shutdown` → `taskkill /T`, with a stale-sidecar reap matched
  on **both PID and image name**.

## BYO-key: never on disk in plaintext

- **At rest:** OS credential store (Windows Credential Manager / macOS Keychain) via
  `flutter_secure_storage`, one entry per provider; the vault is effectively write-only in the UX.
- **In use:** injected into `os.environ` per-run and unconditionally restored on context exit.
- **Persistence:** the run manifest writes only named summary fields; no code path serializes
  `api_keys` to disk, and demo runs strip keys before the job is even stored.
- **This invariant is regression-tested**, not just asserted: `test_vendor_and_provider_keys_never_touch_disk`
  (`tests/test_api_sidecar.py`) drives a full run with sentinel keys and asserts none appear in **any**
  persisted byte under the results dir; `test_env_keys_requires_bearer` asserts the plaintext-key import
  endpoint is bearer-gated and never public.
- **Import path:** `/env-keys` can surface `.env` keys for a one-time import into the keychain —
  loopback + bearer only, and **must never be exposed on a remote surface** (enforced by test).

## Controls in place (with references)

| Control | Reference |
|---|---|
| Loopback-only bind on an ephemeral port | `services/api/__main__.py` (`bind 127.0.0.1:0`) |
| Per-launch bearer middleware on all non-public routes | `services/api/app.py` (`_bearer_auth`, `_PUBLIC_PATHS`) |
| Strong, fresh-per-launch token | `services/api/__main__.py` (`secrets.token_urlsafe(32)`) |
| Token in `Authorization` header only (never URL) | `packages/quorum_core/lib/src/api_client.dart`, `sse_transport.dart` |
| Access logging suppressed | `services/api/__main__.py` (uvicorn `log_level=warning`) |
| Write-only OS-keychain vault, per-provider entries | `apps/desktop/lib/services/key_vault.dart` |
| Per-job credential isolation with guaranteed restore | `tradingagents/runtime/isolation.py` (`JobIsolationContext`) |
| Manifest persistence uses a non-secret field allowlist | `services/api/jobs.py` (`_manifest_dict`, `_persist`) |
| Demo runs strip `api_keys` before the job is stored | `services/api/app.py` (`create_run`) |
| Parent-death watchdog / self-exit | `services/api/__main__.py` (`_pid_alive`) |
| CI runs with a read-only token | `.github/workflows/ci.yml` (`permissions: contents: read`) |
| Secret-scan gate on commits | `.github/workflows/secret-scan.yml` + `.gitleaks.toml` |

## Residual risks (honest)

- **Keys in process memory / env for a run's lifetime** *(Low — accepted).* For a pro/vibe run, keys
  are held in `Job.request` in memory and in `os.environ` during the run. The **OS process + user
  account boundary** is the trust boundary for a single-user desktop; the mitigation is to never add
  crash-reporting/telemetry that captures env or locals.
- **Bearer token mirrored into `QUORUM_API_TOKEN` env** *(Low — accepted).* It is inherited by any
  child the sidecar spawns; scope is the local machine. If an untrusted subprocess is ever spawned,
  scrub the var from its environment.
- **No origin/rate-limit hardening on the loopback API** *(Low — accepted for V1).* The bearer
  requirement blocks token-less calls; an origin/Host allowlist is only needed for a future
  remote/mobile surface (and `/env-keys` must be hard-blocked there).
- **Engine stdout is not secret-filtered beyond the handshake line** *(Low).* The token handshake line
  is never logged; keep the engine's stdout/stderr free of provider keys (it prints none today).
- **No code-signing on early builds** *(known, documented — not a vulnerability).* Deferred to a
  1.x/V2 fast-follow ([ADR 0007](decisions/0007-defer-code-signing-to-v2.md)); unsigned installers run
  normally but show a first-run SmartScreen prompt.

*(A future remote/mobile surface — post-V1 — changes several of these from "accepted" to "must-fix":
the loopback assumption, `/env-keys` exposure, and origin hardening. They are called out here so that
work starts from an honest baseline.)*
