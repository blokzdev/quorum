# Phase 4 — V1 Release & Hardening

> Status: **plan-locked** (merged to `main` 2026-07-06, PR #32). Phase 3 shipped 2026-07-06 (PR #29,
> `0a7ad57`). Phase 4 takes the validated, feature-complete app to an **unsigned 1.0.0 Windows GA**: a
> security sweep + a secret-scan gate, CI merge-hardening, a small bounded **UX-integrity** pass closing the
> four V1-blocking defects from the Phase-4 recon audit, end-to-end release-pipeline validation, and
> unsigned-release readiness. **Production code-signing is deferred to a post-1.0 (1.x / V2) fast-follow**
> ([ADR 0007](decisions/0007-defer-code-signing-to-v2.md), founder call 2026-07-06) — so **Phase 4 carries
> zero paid spend.** Scope wall ([CLAUDE.md](../CLAUDE.md) → Operating doctrine) applies at full strength — a
> "hardening" phase is a scope-creep sink, so every subphase is boxed with **falsifiable exit criteria**, and
> the audit's non-blocking findings are captured to [backlog.md](backlog.md), not absorbed.

## Framing

Phase 3 left the app **feature-complete and CI-green** but **not release-hardened**: the release CI
(`packaging.yml`) has never been verified end-to-end, no per-provider freeze regression guards the frozen
installer, there is no CI secret-scan gate on a public repo, and there is no `SECURITY.md` / threat model
for a public tool that handles user API keys. Phase 4 closes exactly those gaps — and nothing else. The engine
package `tradingagents` stays frozen; all changes are additive.

**Signing is deferred, not skipped.** An unsigned installer + app run **100% normally** (signing is
trust/reputation, not functionality); our per-user / no-admin installer even avoids the UAC "Unknown
publisher" prompt. The cost is a first-run SmartScreen *"Windows protected your PC"* warning (dismissable),
no accumulating publisher reputation across releases, and a higher AV false-positive risk on the
PyInstaller sidecar. Phase 4 **mitigates** those (P4.4) and **retains the `-Sign` seam** so V2 signing is a
wiring-only change. Full rationale + the free/cheap cert research: [ADR 0007](decisions/0007-defer-code-signing-to-v2.md).

## Phase-4 recon audit (informs P4.2; provenance for the backlog)

A golden-grounded UI/UX/a11y audit swept all 7 surfaces (Workflow, one agent/surface, find →
adversarial-verify; every finding grounded in a committed golden PNG the agent Read, or a code file:line —
this env cannot live-capture the Flutter window). Result: **23 findings, 21 CONFIRMED / 2 REJECTED / 0
UNGROUNDED** (no hallucinated pixels). Executive triage (I own the final pass):

- **4 KEEP → P4.2 exit criteria** (below): `a11y-01` sub-AA chips, `set-02`+`tok-01` washed-out Settings
  H1 in the committed goldens, `shell-01` shell chrome has zero golden coverage, `set-01` data-sources
  stored key has no vendor label.
- **2 REJECT:** `hub-02` (as-of caveat weight — defensible: amber = launch-blocking gate vs grey = info);
  `hub-03` (no Hub disclaimer — the *presence* question rolls into P4.2's shell-chrome check, not a Hub bug).
- **16 DEFER → backlog** (provenance `P4-recon`), drained at phase-end: debate-terminal live-state polish
  (`term-01/02/03`, bet #3), capability-gate visual weight (`dt-01/02`, bet #2), design-token scale system
  (`tok-02/03`), remaining a11y polish (`a11y-02..05`), minor consistency (`hub-01`, `set-03`, `shell-02/03`).

The blocking set is **small and coherent** (2 verification-integrity + 1 a11y + 1 finish), so it is absorbed
as a bounded subphase — **not** spun out as a separate UX-hardening phase.

## Phase cadence (set once)

- **Merge model:** subphase PRs are **self-merged to `main` as-you-go** — the founder **delegated merge
  authority (2026-07-06)** given the verification rigor. No integration branch; `main` stays releasable. Each
  self-merge is gated on **full CI green** (ruff + pytest + flutter analyze/test/goldens/build + clean-install
  smoke) **and a fresh-context pre-merge review** of the diff, with golden render-to-PNG (Read the PNG) for
  any visual change. **Still surfaced, never self-merged:** the **GA publish** (tag + release 1.0.0 —
  outward-facing, irreversible) and anything security/cost/contract/scope.
- **Cost boundary:** **entirely free tier** — Ollama + demo + the shared Gemini test key + free data-vendor
  keys + free public-repo CI. **Zero paid spend** (signing deferred per ADR 0007). If anything would cost
  money, it stops and surfaces first.
- **Sensitive ops (surface, never self-approve):** the **GA publish/release** (tag + distribute 1.0.0),
  publishing, and any contract/scope change. *(Merges to `main` are founder-delegated — see the merge model;
  no cert purchase and no key rotation this phase — the shared dev/CI Gemini key stays; rotation is post-V1.)*
- **Verification:** unchanged bar — ruff + pytest + flutter analyze/test/goldens/build + clean-install smoke;
  golden render-to-PNG (Read the PNG) for visual claims; **real-path** (not demo) for freeze + install proofs.

## Subphases

Order follows the dependency graph: **P4.1** (repo + merge guards) first, so the merge-as-you-go work is
protected; **P4.2** (UX-integrity, pure Flutter/Dart) next; **P4.3** (release pipeline) validates the *final*
shippable installer after the code is done — release-artifact CI belongs late; **P4.4** (unsigned-release
readiness) needs P4.3's installer to screenshot + submit; **P4.5** closes out. None require spend.

### P4.1 — Security + CI merge-hardening

- [x] **P4.1a Secret-scan gate** — added `.gitleaks.toml` (extends the default ruleset; allowlists the fake
  fixtures **by value, never by whole file/path** — the fresh-context review caught that a directory-path
  allowlist would mask an entire tree, so a real key committed under `tests/` is still caught) and
  `.github/workflows/secret-scan.yml` (gitleaks, full-history, read-only, on push+PR; free for public repos).
  *Follow-up:* add `secret-scan` as a required status check on `main` (branch-protection toggle). *(The shared
  Gemini `.env` key is a **dev/CI-only credential** — gitignored, never shipped, separate from the product's
  per-run keychain BYOK; rotation deferred to post-V1.)*
- [x] **P4.1b Required merge gate** — the **full flutter job** (analyze + test + goldens + build) is a
  **required status check on `main`** (founder set it in branch protection, 2026-07-06), so merge-as-you-go
  can't land a red commit (closes the P3 slice-verify gap). Fixed the stale `ci.yml` "8 goldens" comment
  (now 14). *Follow-up (branch-protection toggle):* add ruff + pytest + secret-scan as required checks too.
- [x] **P4.1c Security docs + posture re-assert** — added `SECURITY.md` (GitHub private-advisory disclosure
  policy + scope) and `docs/security.md` (threat model: assets, the 5 trust boundaries, the loopback
  bearer-token + ephemeral-port + `QUORUM_PARENT_PID` model, BYO-key never-on-disk, honest residual risks).
  **Adversarial-validate correction:** the recon flagged keys-never-on-disk + `/env-keys` as *untested*
  residuals — **both were already regression-tested** (`test_vendor_and_provider_keys_never_touch_disk`
  byte-scans every persisted file for sentinel keys; `test_env_keys_requires_bearer` gates the plaintext-key
  endpoint, now also asserting it's not in `_PUBLIC_PATHS`), so no new key-safety test was needed. The
  frozen-path byte-scan re-verify folds into **P4.3** (when the installer is actually built).
  *Exit (falsifiable):* the secret-scan gate runs green on the repo and **fails red** on a planted dummy key
  (verify with a scratch commit on the PR branch); the full flutter job is a **required check on `main`** (a
  red flutter job blocks the merge — proven by the merge model); `SECURITY.md` + `docs/security.md` merged;
  the keys-never-on-disk invariant stays guarded by `test_vendor_and_provider_keys_never_touch_disk` (green).

### P4.2 — UX-integrity *(the 4 KEEP audit findings)*

- [x] **P4.2a A11y contrast sweep** (`a11y-01`) — added a pure `accessibleTint(hue, surface)` (contrast.dart)
  that lifts a sub-AA tinted-chip ink to ≥4.5:1 and is a no-op for hues that already pass; wired into the
  pinned badge, `_SignalChip`, `_RatingPill`. Locked with `wcagContrast` tests. **Fresh-review catch fixed:**
  the `_SignalChip` inside the risk-verdict ribbon sits on the ribbon's own `c@0.08` tint, so a Sell (`down`)
  chip/label stayed ~4.2:1 despite the sweep — now targets the composited ribbon bg (regression-tested). One
  golden re-baselined (`terminal_midrun`, isolated-diff-verified = only the confidence chip). PR #35.
- [x] **P4.2b Settings-H1 render/golden integrity** (`set-02`+`tok-01`) — **root-caused by empirical
  bisection:** the H1 code was always correct; the artifact was a **golden-harness capture bug** —
  `matchesGoldenFile(find.byType(SettingsBody))` rasterised the non-RepaintBoundary `SettingsBody` at a
  fractional offset, so the 22px H1 anti-aliased into a faint/pink-fringed/doubled glyph. Proven: identical
  state + `find.byType(Scaffold)` → crisp; `find.byType(SettingsBody)` → the artifact. **Fix = capture the
  Scaffold** (test-only, no product code change). 5 goldens re-baselined (settings ×2, dream_team ×3); Read +
  verified crisp H1, all other content pixel-equivalent. 149 flutter + analyze green.
- [ ] **P4.2c Shell-chrome golden coverage** (`shell-01`) — add a `QuorumShell` golden (title bar + nav tabs
  + caption buttons, in active/inactive states) and Read it. This closes the CLAUDE.md golden-verification
  gap on the make-or-break frameless chrome and lets us confirm, in one place: nav active-state, caption
  buttons, the title-bar seam, cross-surface brand consistency, **and** whether the "research, not financial
  advice" disclaimer is present in the persistent chrome (the `hub-03` posture question).
- [x] **P4.2d Data-sources vendor-key label** (`set-01`) — the required-key field now prefixes the vendor
  name (`_ApiKeyField.label` threaded into the visible `_FieldLabel`): "Alpha Vantage API key" / "FRED API
  key" in both empty and stored states, so a stored key is attributable even when its vendor dropdown is rows
  away. The Model Studio provider key (no label, under its Provider header) stays "API key" — so only the
  data_sources golden re-baselined. Widget assertions updated to the vendor-labelled text; 149 flutter + analyze green.
  *Exit (falsifiable):* a contrast test asserts every audited chip/badge/pill ≥4.5:1 (fails today); the
  Settings goldens show a full-contrast H1 (with a diff justification); a shell golden exists + is Read-verified;
  a data-sources golden asserts the vendor name is visible next to the stored badge; full flutter suite green.

### P4.3 — Release pipeline end-to-end

- [ ] **P4.3a `packaging.yml` e2e + install smoke** — trigger `packaging.yml` via a real `workflow_dispatch`
  (unblocked — it's on `main`) and confirm it produces a working (unsigned) installer artifact; add a
  **clean-VM install-and-launch smoke** (install the built `.exe` on a fresh runner, launch, hit `/healthz`,
  uninstall) — closing the "builds the installer but never runs it" gap. *(Runner-local install files carry no
  Mark-of-the-Web, so SmartScreen doesn't gate the CI smoke — unsigned is fine here.)* Run after P4.2 so the
  validated artifact reflects the final UX code.
- [ ] **P4.3b Per-provider freeze regression** — add the **per-provider freeze regression test** (a headless
  real run per provider family asserting a *non-empty* report — the P2.6b HIGH proved a demo-only check can't
  catch a missing provider package in the freeze).
  *Exit (falsifiable):* a `workflow_dispatch` run is green and yields a launchable (unsigned) installer; the
  install smoke is green (a broken installer fails it); the freeze test is green and **fails red** when a
  provider package is removed from the spec.

### P4.4 — Unsigned-release readiness *(the deferred-signing mitigations — [ADR 0007](decisions/0007-defer-code-signing-to-v2.md))*

- [ ] **P4.4a First-run UX docs** — a README / download-page walkthrough of the **"More info → Run anyway"**
  SmartScreen step with a screenshot (of P4.3's built installer), set honestly (unsigned early release;
  signing coming in a later version), so a first-time user isn't scared off by the warning.
- [ ] **P4.4b AV false-positive pre-submission** — before launch, submit the built installer + the frozen
  `quorum_sidecar.exe` to **Microsoft Defender** ([file submission](https://www.microsoft.com/en-us/wdsi/filesubmission))
  to reduce the PyInstaller false-positive risk; note the `-Sign` seam is retained for V2.
  *Exit (falsifiable):* the download page documents the Run-anyway step with a screenshot; the Defender
  submission is filed (reference recorded); `build_installer.ps1 -Sign` still works (self-signed dev path
  intact) so V2 signing is a wiring-only change.

### P4.5 — GA close-out

- [ ] **P4.5a Version + docs reconciliation** — reconcile the version (pubspec is already `1.0.0+1`; the build
  script/docs/examples still say `0.2.0`); refresh `CHANGELOG.md`, `README.md` (GA posture, unsigned-release
  note), `roadmap.md`, and this plan's checkboxes.
- [ ] **P4.5b Completeness-critic + scope audit + publish** — a fresh-context pass (any shipped capability with
  no exit criterion is unsanctioned creep); backlog drained (triage the 16 `P4-recon` items + P3 carryovers
  into the next phase or won't-do); then **surface the 1.0.0 GA publish to the founder** (tag + GitHub release
  + installer distribution — the one outward-facing act not self-merged).
  *Exit (phase):* an **unsigned** Windows installer installs → launches → runs a real analysis → uninstalls
  cleanly on a fresh machine; the first-run Run-anyway UX is documented + the Defender submission filed;
  release CI is green end-to-end with the freeze + install-smoke + per-provider guards; the 4 UX-integrity
  criteria pass; the security docs + secret-scan + required-merge gate are in; CI stays green (Python +
  Flutter); all subphases merged to `main`; **1.0.0 tagged + published (founder-surfaced)**.

## Not in Phase 4 (deferred — captured, not dropped)

- **Production code-signing** → **post-1.0 (1.x / V2)** ([ADR 0007](decisions/0007-defer-code-signing-to-v2.md),
  founder call 2026-07-06). The `-Sign` seam is retained; recommended cert then is Certum Open Source
  (~€29/yr) or Azure Artifact Signing (~$120/yr). Revisit when distribution traction justifies the spend.
- **macOS port + notarization** → roadmap **P13** (post-V1). Phase 4 ships a **Windows-only** 1.0.0 GA.
- **Shared Gemini test-key rotation** → **post-V1** (founder call 2026-07-06). It's a dev/CI-only credential
  that never ships (gitignored, not bundled), so it's dev-hygiene, not a GA gate; the secret-scan gate (P4.1a)
  is the part that protects the public repo. Stays in `docs/backlog.md`.
- **The 16 `P4-recon` audit refinements** → [backlog.md](backlog.md) (debate-terminal liveness, capability-gate
  weight, token-scale system, a11y polish, minor consistency). Vision-aligned ones (bet #2/#3) noted for a
  post-V1 premium-feel pass on the roadmap.
- **Auto-update / distribution maturity** (P15), **Track Record / hosted signal layer / paper-trading /
  brokerage / mobile remote** — all post-V1 per [roadmap.md](roadmap.md).
