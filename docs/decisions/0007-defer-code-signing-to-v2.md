# ADR 0007 — Defer production code-signing to V2 (ship 1.0.0 unsigned)

- **Status:** Accepted (2026-07-06) — Phase 4 ([phase-4-plan.md](../phase-4-plan.md))
- **Context:** Phase 4 takes the feature-complete app to a Windows 1.0.0 GA. Code-signing is the phase's
  only paid line and its only founder-gated spend.
- **Deciders:** ganesh (founder) chose to defer, from a researched recommendation (free/cheap options +
  the unsigned tradeoffs).
- **Supersedes/relates:** the "production keystore signing is Phase 3/4" note in
  [ADR 0005](0005-installer-format.md); the `-Sign` seam in `packaging/build_installer.ps1` is retained.

## Context

Windows Authenticode signing is about **trust/reputation, not functionality** — an unsigned installer
and app run identically. Signing costs money and/or setup: the only genuinely free publicly-trusted path
is **SignPath Foundation** (OSS), which (a) shows **"SignPath Foundation"** as the publisher — not the
Quorum brand — and (b) forbids affiliated proprietary/commercial components, which our **open-core** model
(paid hosted server-side layer) puts at eligibility risk. The cheap paid options are **Certum Open Source**
(~€29/yr renewal, personal-name publisher, hardware token) and **Azure Artifact Signing** (~$120/yr,
company/identity publisher, cloud HSM, CI-native). Two Windows facts shape the tradeoff:

- Our installer is **per-user / no-admin** (Inno Setup, `%LOCALAPPDATA%`), so an unsigned build triggers
  **no UAC "Unknown publisher" elevation prompt**.
- Microsoft removed EV's instant-SmartScreen advantage in 2026; **all** certs now build reputation
  gradually with download volume — so signing buys reputation *over time*, not an instant clean install.

## Decision

**Ship 1.0.0 unsigned; defer production code-signing to a post-1.0 (1.x / V2) fast-follow.** Retain the
`-Sign` seam in `build_installer.ps1` and keep the signing wiring CA-agnostic so a cert can be added later
with no rework. Revisit when distribution traction justifies the spend (recommended cert then: Certum Open
Source or Azure Artifact Signing — see the research in the phase-4 HUMAN.md thread).

## Consequences

- **+** Phase 4 carries **zero paid spend** and no founder-gated cost; fastest path to GA.
- **+** Fully reversible/additive — signing lands later via the retained seam with no architecture change.
- **−** First-run **SmartScreen "Windows protected your PC"** warning (dismissable via *More info → Run
  anyway*); a real drop-off risk and a rough first impression for a premium product.
- **−** **No accumulating publisher reputation** — the warning recurs on every release, and the reputation
  clock only starts once we sign in V2.
- **−** Higher **antivirus false-positive** risk on the PyInstaller-frozen `quorum_sidecar.exe`.

## Mitigations (Phase 4, P4.4)

- A README / download-page walkthrough of the **"More info → Run anyway"** step, with a screenshot.
- Pre-submit the installer to **Microsoft Defender** ([file submission](https://www.microsoft.com/en-us/wdsi/filesubmission))
  before launch to reduce AV false-positives.
- Keep the `-Sign` seam documented so V2 signing is a wiring-only change.

## Alternatives considered

- **Sign now with Certum Open Source (~€29/yr)** — cheapest signed path, keeps the premium first
  impression, fits the local build flow. **Deferred** by founder call to avoid any spend/setup at GA;
  the delta over unsigned is small in dollars but non-trivial in setup (hardware token) + timeline.
- **Sign now with Azure Artifact Signing (~$120/yr)** — best CI automation + company-name publisher.
  **Deferred** for the same reason; eligibility depends on business entity/location.
- **SignPath Foundation (free)** — **rejected:** "SignPath Foundation" publisher name is off-brand for a
  premium product, and the open-core model risks failing its no-proprietary-affiliate eligibility rule.
