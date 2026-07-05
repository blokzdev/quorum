# ADR 0001 — BYO provider API-key storage

- **Status:** Accepted (2026-06-26)
- **Context:** Phase 2 ([P2.3a](../phase-2-plan.md#p23--settings--model-studio-depends-on-p21bc--p22))
- **Deciders:** Quorum desktop track

## Context

Quorum lets users bring their own LLM-provider API keys (OpenAI, Anthropic, Google, etc.). Today
keys live only in the gitignored `.env`, read by the CLI and the engine. The desktop app does not yet
collect or store keys — `RunController.start()` launches a hardcoded `demo` run and sends no keys.

Phase 2's Model Studio makes real `pro`/`vibe` runs the common path, so the desktop needs to:

1. collect provider keys from the user,
2. store them at rest between launches (so users don't re-enter them every session), and
3. get them to the engine for a run.

The sidecar contract is already designed for this: `POST /runs` (`RunRequest`) accepts an `api_keys`
dict that is **request-scoped and never persisted server-side**; `JobIsolationContext` injects those
keys into `os.environ` for the duration of a single job and restores the environment on exit
(see [services/api/app.py](../../services/api/app.py),
[services/api/jobs.py](../../services/api/jobs.py),
[tradingagents/runtime/isolation.py](../../tradingagents/runtime/isolation.py)). The engine reads
keys from `os.environ` at graph-construction time on the host machine.

Post-V1, a mobile app will act as a **LAN/WAN remote over the same API**, with the desktop/host
running the sidecar. That constraint matters: provider keys should live on the *sidecar host*, never
on the phone.

## Decision

**Store BYO keys in the OS credential manager via `flutter_secure_storage`, one entry per provider,
and inject them per-run through the existing `RunRequest.api_keys` field.**

Concretely:

- **Primitive:** `flutter_secure_storage` (v10.x). On Windows it is backed by **Windows Credential
  Manager** (DPAPI under the hood + AES-GCM); on macOS/iOS by **Keychain**; on Linux by **libsecret**;
  on Android by Keystore. The macOS port needs **zero code change**.
- **Granularity:** **one entry per provider** (e.g. `quorum_apikey_anthropic`), never a single JSON
  blob. Windows Credential Manager has a hard `CRED_MAX_CREDENTIAL_BLOB_SIZE` of **2560 bytes**;
  individual keys (≈50–200 bytes) have ample headroom, and per-entry storage avoids silent
  oversized-blob write failures.
- **Seed:** on first launch, offer a one-time import of any keys found in the gitignored `.env` into
  secure storage. The CLI keeps using `.env` unchanged.
- **Injection / placement:** the desktop reads keys at run-start and passes them in `RunRequest.api_keys`
  on `POST /runs`. The **sidecar stays stateless** — it injects per job via `JobIsolationContext` and
  restores on exit. No engine or sidecar contract change is required.
- **Hygiene:** provide a "Forget all keys" action in Settings (credential-manager entries persist
  across app uninstall, scoped to the OS user — not the app).

## Security posture (stated honestly)

This protects keys at rest against the realistic everyday threats for a local desktop tool:

- another OS user on the same machine cannot read them (per-user credential isolation),
- they are not in plaintext in a config file or the repo,
- they are not exposed to offline disk/backup theft without the user's DPAPI master key,
- they never travel to or persist on a remote phone client.

It does **not** — and on Windows *cannot* — protect against **malware or any process running as the
same logged-in user** with the app's privileges: Windows Credential Manager uses DPAPI, and any
same-user process can call `CryptUnprotectData` to decrypt the values (tools like LaZagne / DonPAPI
automate exactly this). It also cannot protect keys once they are loaded into the running process's
memory (a debugger attached to the app can extract them).

This is a **fundamental Windows design constraint accepted by every comparable local BYO-key tool** —
VS Code, JetBrains IDEs, GitHub CLI, and Cursor all store user secrets in the OS credential manager
with the same threat model. It is the industry-standard posture for a local research tool, not
security theater, and not a flaw in our implementation.

User-facing docs should say plainly: *"API keys are stored using your operating system's credential
manager, which protects them from other users and file theft, but not from malware running on your
machine under your account."*

## Alternatives considered

- **Master-passphrase-encrypted vault (unlock at launch).** Adds real defense-in-depth against
  offline/file-dump attacks, but: (a) UX friction (unlock every launch), (b) KDF complexity
  (Argon2id), and (c) it does **not** stop a compromised *running* process from decrypting after
  unlock. **Deferred** as an *opt-in* "extra protection" toggle, not the default.
- **Write keys to the sidecar/engine `.env`.** Simpler (engine reads natively), but breaks the clean
  stateless-sidecar invariant, persists keys server-side, and is wrong for the mobile-remote case
  (keys would sit on whatever runs the engine, and the desktop would manage a server-side file).
  **Rejected.**
- **`.env`-only (status quo).** No new storage; minimal work — but plaintext on disk, manual file
  editing, no Settings path, and a poor base for Model Studio. **Rejected** except as a stopgap.
- **Custom encryption / encrypted file with a hardcoded key.** Rolls our own crypto and bakes the key
  into the binary's attack surface. **Rejected** — delegate to the OS.

## Consequences

- Windows build/CI agents need **Visual Studio Build Tools with C++ ATL** for the
  `flutter_secure_storage_windows` backend — a build-time dependency to wire into the P2.5 signed-
  installer pipeline.
- Keys are sent over the loopback API in the `RunRequest` body on every run. Safe today
  (`127.0.0.1` + per-launch bearer token), but when the mobile remote exposes the API over LAN/WAN,
  the transport **must** be TLS + auth, and the design should have the *host* inject its own stored
  keys rather than the phone transmitting keys.
- Re-verify the `JobIsolationContext` `os.environ` snapshot/restore once real BYO-key runs are the
  common path (so a subsequent `demo` job can't observe a prior run's credentials).
- Ensure the `.env` import/seed never re-seeds the stale shared Gemini test key (pending rotation in
  P2.0b).

## Sources

- [flutter_secure_storage — pub.dev](https://pub.dev/packages/flutter_secure_storage)
  (160/160 score, ~3M downloads, verified publisher; Windows = Credential Manager, macOS = Keychain,
  Linux = libsecret).
- [Microsoft Learn — CREDENTIALW structure (`CredentialBlobSize`, 2560-byte limit)](https://learn.microsoft.com/en-us/windows/win32/api/wincred/ns-wincred-credentialw)
- [Microsoft Learn — Kinds of Credentials / Credentials Management](https://learn.microsoft.com/en-us/windows/win32/secauthn/kinds-of-credentials)
- [JetBrains Platform — Persisting Sensitive Data (OS credential store precedent)](https://plugins.jetbrains.com/docs/intellij/persisting-sensitive-data.html)
- [VS Code — where extension secrets are stored (OS credential store precedent)](https://github.com/microsoft/vscode-discussions/discussions/748)
- DPAPI same-user threat model: [Threat Hunter Playbook — Data Protection API](https://threathunterplaybook.com/library/windows/data_protection_api.html),
  [The Hacker Recipes — DPAPI secrets](https://www.thehacker.recipes/ad/movement/credentials/dumping/dpapi-protected-secrets)
