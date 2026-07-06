# Phase 4 — V1 Release & Hardening

> Status: **plan-locked (proposed)** — awaiting founder approval of this docs PR + the one paid-spend gate
> (production code-signing cert; see [HUMAN.md](../HUMAN.md) §1/§2). Phase 3 shipped to `main` 2026-07-06
> (PR #29, `0a7ad57`). Phase 4 takes the validated, feature-complete app to a **signed 1.0.0 Windows GA**:
> production code-signing, a security sweep + secret rotation, end-to-end release CI, and a small bounded
> **UX-integrity** pass that closes the four V1-blocking defects surfaced by the Phase-4 recon audit.
> Scope wall ([CLAUDE.md](../CLAUDE.md) → Operating doctrine) applies at full strength — a "hardening" phase
> is a scope-creep sink, so every subphase is boxed with **falsifiable exit criteria**, and the audit's
> non-blocking findings are captured to [backlog.md](backlog.md), not absorbed.

## Framing

Phase 3 left the app **feature-complete and CI-green** but **not shippable**: it is signed only with a
**debug self-signed cert** ([`packaging/build_installer.ps1`](../packaging/build_installer.ps1) `-Sign`),
the release CI (`packaging.yml`) has never been verified end-to-end, no per-provider freeze regression
guards the frozen installer, the shared Gemini test key is unrotated, and there is no `SECURITY.md` /
threat model for a public tool that handles user API keys. Phase 4 closes exactly those gaps — and nothing
else. The engine package `tradingagents` stays frozen; all changes are additive.

**This is the first real spend.** Production signing (a code-signing certificate) and paid CI are where
Phase 4 crosses the cost boundary. Spend is **founder-gated** — no cert is purchased and no paid service is
provisioned without an explicit go (HUMAN.md §1). The signing *wiring* is built CA-agnostic so it does not
block on the cert-vendor choice.

## Phase-4 recon audit (informs P4.4; provenance for the backlog)

A golden-grounded UI/UX/a11y audit swept all 7 surfaces (Workflow, one agent/surface, find →
adversarial-verify; every finding grounded in a committed golden PNG the agent Read, or a code file:line —
this env cannot live-capture the Flutter window). Result: **23 findings, 21 CONFIRMED / 2 REJECTED / 0
UNGROUNDED** (no hallucinated pixels). Executive triage (I own the final pass):

- **4 KEEP → P4.4 exit criteria** (below): `a11y-01` sub-AA chips, `set-02`+`tok-01` washed-out Settings
  H1 in the committed goldens, `shell-01` shell chrome has zero golden coverage, `set-01` data-sources
  stored key has no vendor label.
- **2 REJECT:** `hub-02` (as-of caveat weight — defensible: amber = launch-blocking gate vs grey = info);
  `hub-03` (no Hub disclaimer — the *presence* question rolls into P4.4's shell-chrome check, not a Hub bug).
- **16 DEFER → backlog** (provenance `P4-recon`), drained at phase-end: debate-terminal live-state polish
  (`term-01/02/03`, bet #3), capability-gate visual weight (`dt-01/02`, bet #2), design-token scale system
  (`tok-02/03`), remaining a11y polish (`a11y-02..05`), minor consistency (`hub-01`, `set-03`, `shell-02/03`).

The blocking set is **small and coherent** (2 verification-integrity + 1 a11y + 1 finish), so it is absorbed
as a bounded subphase — **not** spun out as a separate UX-hardening phase.

## Phase cadence (set once)

- **Merge model:** subphase PRs self-merged into a `phase-4` integration branch; `main` untouched until the
  phase-end `phase-4 → main` merge (**founder-approved**, never self-approved). This plan-lock docs PR
  merges to `main` first (founder-approved) to seed the phase.
- **Cost boundary:** unchanged free tier (Ollama + demo + the shared Gemini test key + free data-vendor
  keys) **plus one founder-approved paid line: a production code-signing certificate** (≈$120/yr Azure
  Trusted Signing, recommended, pending eligibility; ≈$200–400/yr OV cert fallback) and any paid CI minutes.
  **No paid spend without an explicit go**; I surface exact cost + eligibility before purchase.
- **Sensitive ops (surface, never self-approve):** the cert purchase + any signing/keystore step, the Gemini
  key rotation, the `phase-4 → main` merge, publishing/GA, and any contract/scope change.
- **Verification:** unchanged bar — ruff + pytest + flutter analyze/test/goldens/build + clean-install smoke;
  golden render-to-PNG (Read the PNG) for visual claims; **real-path** (not demo) for signing, freeze, and
  install proofs.

## Subphases

Recommended order de-risks spend: **P4.1** (security, no spend) and **P4.4** (UX-integrity, no spend, closes
the audit blockers) can start immediately; **P4.2** (signing) waits on the founder's cert go; **P4.3**
(release CI) partly depends on P4.2's signing wiring; **P4.5** closes out.

### P4.1 — Security sweep + secret hygiene *(no spend)*

- [ ] **P4.1a Secret rotation + scan gate** — rotate the **shared Gemini test key** (founder rotates in the
  Google console → hands me the new key for the gitignored `.env`; old key invalidated). Add a CI
  **secret-scan** step (e.g. `gitleaks`/`trufflehog` or a pinned ruff-adjacent check) that fails on any
  committed key pattern, so a future leak can't merge.
- [ ] **P4.1b Security docs + posture re-assert** — add a `SECURITY.md` (coordinated vulnerability-disclosure
  policy) and a lightweight **threat model** (`docs/security.md`: assets = user API keys + local sidecar
  boundary; the bearer-token + ephemeral-port + `QUORUM_PARENT_PID` model; BYO-key never-on-disk). Re-assert
  keys-never-on-disk on the **frozen** path (byte-scan a real spawned-installer run).
  *Exit (falsifiable):* the old Gemini key is revoked (a run with it fails auth); the secret-scan gate is
  green and **fails red** on a planted dummy key in a scratch file; `SECURITY.md` + `docs/security.md` merged;
  a frozen-path run leaves no key on disk or in logs (byte-scan).

### P4.2 — Production code-signing *(FIRST REAL SPEND — founder-gated)*

- [ ] **P4.2a Cert path + provisioning** *(founder action)* — confirm eligibility and provision the chosen
  cert (recommended: **Azure Trusted Signing**; fallback: an OV cert). ADR **0007** records the choice +
  rationale + SmartScreen-reputation posture.
- [ ] **P4.2b Signing wiring (CA-agnostic)** — wire [`build_installer.ps1`](../packaging/build_installer.ps1)
  + [`packaging.yml`](../.github/workflows/packaging.yml) to sign `quorum.exe`, `quorum_sidecar.exe`, and the
  installer with the **production** cert pulled from a secure secret store (GitHub encrypted secret / Azure
  identity), keeping the self-signed path as an explicit `-DevSign` dev fallback. Code is written to be
  cert-vendor-neutral so it lands before the cert is purchased.
  *Exit (falsifiable):* all three binaries + the installer carry a valid production signature
  (`signtool verify /pa` passes; the self-signed subject is gone from a release build); the signing secret is
  never printed in CI logs; ADR 0007 merged.

### P4.3 — Release CI end-to-end *(paid CI minutes)*

- [ ] **P4.3a `packaging.yml` e2e + install smoke** — trigger `packaging.yml` via a real `workflow_dispatch`
  (now unblocked — it's on `main`) and confirm it produces a **signed** installer artifact; add a **clean-VM
  install-and-launch smoke** (install the built `.exe` on a fresh runner, launch, hit `/healthz`, uninstall)
  — closing the "builds the installer but never runs it" gap.
- [ ] **P4.3b Freeze + gate regressions** — add the **per-provider freeze regression test** (a headless real
  run per provider family asserting a *non-empty* report — the P2.6b HIGH proved a demo-only check can't catch
  a missing provider package); make the **full flutter job a required gate on integration-branch merges** (the
  P3 slice-verify gap where sub-PRs merged red); fix the stale `ci.yml` "8 goldens" comment (now 14).
  *Exit (falsifiable):* a `workflow_dispatch` run is green and its artifact is signed; the install smoke is
  green (a broken installer fails it); the freeze test is green and **fails red** when a provider package is
  removed from the spec; the integration-merge gate is documented + enforced.

### P4.4 — UX-integrity *(no spend — the 4 KEEP audit findings)*

- [ ] **P4.4a A11y contrast sweep** (`a11y-01`) — raise the sub-AA text-on-tint elements (pinned cast badge
  4.0:1; `textLo` confidence `_SignalChip` 4.22:1; defensively the SELL `_RatingPill` at 4.60:1) to ≥4.5:1,
  the AA-normal bar P3.4b established. Lock with a pure-Dart `wcagContrast` test, like the existing onAccent
  proof.
- [ ] **P4.4b Settings-H1 render/golden integrity** (`set-02`+`tok-01`) — root-cause the washed-out/ghosted
  "Settings" H1 (code is correct — `brand.textHi`, w700, no opacity — so this is a golden-capture/raster
  artifact enshrined in the committed reference, which renders *differently* across two goldens). Verify the
  real render, fix if live, and re-baseline the affected goldens with a **written visual-diff justification**
  so the committed truth shows the title as the most prominent element.
- [ ] **P4.4c Shell-chrome golden coverage** (`shell-01`) — add a `QuorumShell` golden (title bar + nav tabs
  + caption buttons, in active/inactive states) and Read it. This closes the CLAUDE.md golden-verification
  gap on the make-or-break frameless chrome and lets us confirm, in one place: nav active-state, caption
  buttons, the title-bar seam, cross-surface brand consistency, **and** whether the "research, not financial
  advice" disclaimer is present in the persistent chrome (the `hub-03` posture question).
- [ ] **P4.4d Data-sources vendor-key label** (`set-01`) — show the vendor name in the required-key field
  label in **both** empty and stored states (e.g. "Alpha Vantage API key" not a bare "API key").
  *Exit (falsifiable):* a contrast test asserts every audited chip/badge/pill ≥4.5:1 (fails today); the
  Settings goldens show a full-contrast H1 (with a diff justification); a shell golden exists + is Read-verified;
  a data-sources golden asserts the vendor name is visible next to the stored badge; full flutter suite green.

### P4.5 — GA close-out

- [ ] **P4.5a Version + docs reconciliation** — reconcile the version (pubspec is already `1.0.0+1`; the build
  script/docs/examples still say `0.2.0`); refresh `CHANGELOG.md`, `README.md` (GA posture), `roadmap.md`,
  and this plan's checkboxes; ADRs in place (0007 signing).
- [ ] **P4.5b Completeness-critic + scope audit** — a fresh-context pass (any shipped capability with no exit
  criterion is unsanctioned creep); backlog drained (triage the 16 `P4-recon` items + P3 carryovers into the
  next phase or won't-do); review the `phase-4 → main` PR **in slices**, then founder-approve + merge → **1.0.0
  GA**.
  *Exit (phase):* a **signed** Windows installer installs → launches → runs a real analysis → uninstalls
  cleanly on a fresh machine; `signtool verify` passes; the security docs + rotation are in; release CI is
  green end-to-end with the freeze + install-smoke + per-provider guards; the 4 UX-integrity criteria pass;
  CI stays green (Python + Flutter); `phase-4 → main` merged as **1.0.0**.

## Not in Phase 4 (deferred — captured, not dropped)

- **macOS port + notarization** → roadmap **P13** (post-V1). Phase 4 ships a **Windows-only** 1.0.0 GA; a
  multi-platform signed launch is a separate coordination (adds Apple Developer spend). *(Founder call —
  recommended Windows-first.)*
- **The 16 `P4-recon` audit refinements** → [backlog.md](backlog.md) (debate-terminal liveness, capability-gate
  weight, token-scale system, a11y polish, minor consistency). Vision-aligned ones (bet #2/#3) noted for a
  post-V1 premium-feel pass on the roadmap.
- **Auto-update / distribution maturity** (P15), **Track Record / hosted signal layer / paper-trading /
  brokerage / mobile remote** — all post-V1 per [roadmap.md](roadmap.md).
