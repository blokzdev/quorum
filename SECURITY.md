# Security Policy

Quorum is a **local-first desktop research terminal** — a research/educational tool, **not financial
advice**, that executes **no real-money trades**. It runs a bundled Python engine as a loopback-only
child process and stores your provider API keys in your operating system's keychain. We take the safety
of your credentials and machine seriously. This document covers how to report a vulnerability; for the
architecture, trust boundaries, and threat model, see [`docs/security.md`](docs/security.md).

## Supported versions

Quorum is pre-1.0 and ships from `main`. Security fixes land on `main` and in the latest release; there
is no back-porting to older builds yet. Always run the latest version.

| Version | Supported |
|---|---|
| Latest release / `main` | ✅ |
| Older builds | ❌ (upgrade) |

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.** Instead, use GitHub's private
vulnerability reporting:

1. Go to the repository's **Security** tab → **Report a vulnerability** (GitHub Security Advisories), or
   visit **https://github.com/blokzdev/quorum/security/advisories/new**.
2. Include: what you found, the affected version/commit, reproduction steps, and the impact you observed.

We aim to acknowledge a report within **5 business days** and to keep you updated as we investigate.
Please give us a reasonable window to release a fix before any public disclosure; we're happy to
credit you in the advisory.

## Scope

**In scope** — the Quorum desktop client and the bundled sidecar in this repository, including:
- Credential handling (BYO provider/vendor API keys, the OS-keychain vault, per-run injection).
- The local sidecar boundary (the loopback HTTP API, the per-launch bearer token, process lifecycle).
- The build/release pipeline and CI as it affects distributed artifacts.

**Out of scope** — issues that are not Quorum defects:
- Vulnerabilities in third-party LLM/data providers you bring your own key to (report those upstream).
- Findings that require an already-compromised local machine / another local user with your privileges
  (the OS process + user account boundary is Quorum's trust boundary for a single-user desktop; see
  [`docs/security.md`](docs/security.md) → Residual risks).
- The absence of code-signing on early builds — this is a **known, documented** decision deferred to a
  1.x/V2 fast-follow ([ADR 0007](docs/decisions/0007-defer-code-signing-to-v2.md)), not a vulnerability.

## What we do to protect you

- **Keys never leave your machine by design** — BYO keys are stored in the OS keychain, injected into
  the engine per-run, and are **never written to disk** in a run manifest/report (guarded by a
  regression test) and never sent anywhere but the provider you chose.
- **The engine is loopback-only + bearer-authenticated** — the sidecar binds `127.0.0.1` on an
  ephemeral port and rejects every request without the per-launch token.
- **A secret-scan CI gate** blocks any credential from being committed to this public repository.

Full detail: [`docs/security.md`](docs/security.md).
