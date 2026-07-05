# Backlog — out-of-scope work, captured then deferred

> Append-only, one line per item. **Two capture sources** (CLAUDE.md → Operating doctrine): *reactive* —
> work fails the scope-wall four-checks mid-implementation; and *generative* — the adversarial-validation
> / design fan-out surfaces a vision-aligned adjacency beyond scope (harvest it, don't discard it). Either
> way: append a line and keep moving — capture must be cheaper than doing it; **capture ≠ commit** (acting
> still pays the full four-check wall). Do NOT design, prioritize, or groom mid-phase; **drain at phase
> close-out** (triage into the next phase plan or close as won't-do).
>
> **Routing** — this file is for *homeless enhancements* only. A coherent future-phase **feature/capability**
> goes to [`roadmap.md`](roadmap.md)'s phase band, NOT here. The vision-aligned bar gates entry (advances a
> stated bet or named phase, else drop it for real). A `security` / `correctness` / `data-loss` item does
> NOT belong here — it goes straight to `HUMAN.md` the same session.
>
> Format: `- [YYYY-MM-DD] (subphase) <what> — <enhancement | future-subphase | net-new-scope> — <S/M/L>`

- [2026-06-27] (P2.3 C6) Make the custom Model Studio controls (buttons/chips/depth toggles + nav tabs) keyboard-operable — enhancement (a11y, review LOW) — M
- [2026-06-27] (P2.3 C6) Filled-button WCAG AA contrast (white-on-accent 3.77:1) — darken fill / add an onAccent token; brand decision — enhancement — S
- [2026-06-27] (P2.4) Run Comparison: diff two runs of the same ticker across model configs/dates (P2.4d stretch) — future-subphase — M
- [2026-06-27] (P2.5) Per-role *effort* UI control in Model Studio (the wire seam `spec.effort` already ships dormant) — enhancement — M
- [2026-06-27] (MO) Optional CI/pre-commit check: fail if HUMAN.md "Last AI update" is older than the newest commit touching apps/ or tradingagents/ — enhancement (HITL anti-rot insurance) — S
- [2026-06-27] (Phase 3) Rotate the shared Gemini test key (release hygiene) — future-subphase — S
- [2026-06-27] (P2.5c1) Per-role OpenAI-compatible / Ollama **base-URL field** so a role can pin a custom/local endpoint independent of the global provider (c1 excludes openai_compatible per role to avoid a broken run) — future-subphase (P2.5c2+) — M
- [2026-06-27] (P2.5c1) Non-destructive **"fill only unassigned"** apply-to-all variant (and/or confirm-before-clobber); c1 ships the simpler destructive overwrite — enhancement — S
- [2026-06-27] (P2.5c1) Bench row summary should show **"N roles"** so users see that applying a Bench REPLACES (not merges) the whole Dream Team lineup — enhancement — S
- [2026-06-27] (P2.5c1) **Live-terminal cast list** — surface the resolved roster on the verdict rail the moment a run completes (needs the resolved map plumbed into RunViewState); advances the debate-terminal transparency bet — future-subphase — M
- [2026-07-04] (P2.6c) Flutter version bump is a **coupled goldens re-baseline**: CI pins the exact Flutter 3.38.6 the 8 goldens were byte-exact rasterized on, so bumping Flutter/Dart requires regenerating + Read-verifying all goldens in the same PR (byte-exact by design). Note this on any SDK bump — enhancement (process) — S
- [2026-07-04] (P2.6c) Verify `packaging.yml` end-to-end via one `workflow_dispatch` run once it reaches `main` (workflow_dispatch needs the file on the default branch) — build script + deps confirmed sound, but the CI run (choco Inno, runner CRT/signtool, PyInstaller on the hosted image) is unproven — future-subphase (Phase 3 release CI) — S
- [2026-07-04] (P2.6b) Bedrock in the frozen installer: `langchain_aws` + `boto3` aren't repo deps, so `bedrock_client` is intentionally not bundled — a Bedrock run through the installed app fails. Add the deps + hiddenimports (and validate) if Bedrock support is wanted — future-subphase — M
- [2026-07-04] (P2.6b) Add a **provider-freeze regression test**: a headless real run per provider family (openai-compat + one native cloud) that asserts a non-empty report — the demo contract check can't catch a missing provider package (the P2.6b HIGH slipped past a demo-only "11/11") — enhancement (CI, needs a runner with Ollama/a key) — M
- [2026-07-04] (P2.6a) Harden the stale-reap PID check: `_isLiveSidecar` scans `tasklist` stdout for `contains('$pid')`, which could match a PID substring elsewhere in the row (e.g. a memory figure) — parse the row/CSV properly. Pre-existing (not introduced by the spawn-path change); low risk (guarded by the `/FI IMAGENAME` filter) — enhancement — S
- [2026-06-27] (P2.5c1) **Serve the Dream Team roster via `/catalog`** (ROLE_KEYS + labels + DEEP_ROLES + stages) so the desktop stops hand-mirroring agent_roles.py — kills a whole class of drift (Model Studio + cast list); a contract/endpoint change for a future Model Studio hardening — future-subphase — M
- [2026-06-27] (P2.5c2) **Launch-time capability backstop** — re-check the EFFECTIVE tool-role model at launch (incl. the global quick model that runs unassigned tool roles, and bench/apply-introduced combos) and gate the run, not just the picker. Out of c2 (a new mechanism beyond "assigning… blocked in the UI"); moot today (denylist empty) but real once the denylist grows — future-subphase — M
- [2026-06-27] (P2.5c2) **Surface the `_NON_TOOL_MODELS` denylist** (or a capability column) in `model_catalog` so the block path is exercised by real catalog data, not only injected test flags — enhancement — S
- [2026-06-27] (P2.5c2) **Key-gate "Set in Settings" deep-link** — make the Hub key-gate notice navigate to the Settings provider/key field (c2 ships text-only to avoid nav plumbing) — enhancement — S
