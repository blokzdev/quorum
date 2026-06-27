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
