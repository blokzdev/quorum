import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart';
import '../state/app_surface.dart';
import '../state/capability_gate.dart';
import '../state/hub_provider.dart';
import '../state/run_controller.dart';
import '../state/settings_controller.dart';
import 'quorum_colors.dart';
import 'terminal_screen.dart' show TerminalBody;

/// Reconstruct the terminal's [RunViewState] for a finished run so a cached review re-renders through
/// the same [TerminalBody] (verdict rail, tug-of-war, report cards) — no re-run. Verdict + cost come
/// from the [RunSummary]; the report sections come from `GET /runs/{id}/reports`; every stage/agent is
/// marked done so the pipeline rail reads as complete.
RunViewState cachedRunState(RunSummary s, Map<String, String> sections) {
  final Map<AgentId, NodeStatus> agents;
  final Map<Stage, NodeStatus> stages;
  if (s.phase == RunPhase.done) {
    agents = {for (final ags in stageMeta.values) for (final a in ags.$2) a: NodeStatus.done};
    stages = {for (final st in stageMeta.keys) st: NodeStatus.done};
  } else {
    // A cancelled/partial run only reached the agents whose sections exist — don't overstate the
    // pipeline as fully complete when the header says Cancelled.
    agents = {
      for (final key in sections.keys)
        if (sectionAgent[key] != null) sectionAgent[key]!: NodeStatus.done,
    };
    stages = {
      for (final st in stageMeta.entries)
        if (st.value.$2.every((a) => agents[a] == NodeStatus.done)) st.key: NodeStatus.done,
    };
  }
  return RunViewState(
    runId: s.runId,
    ticker: s.ticker,
    tradeDate: s.tradeDate,
    phase: s.phase,
    stages: stages,
    agents: agents,
    reports: {for (final e in sections.entries) e.key: ReportSection(e.key, e.value, null)},
    cost: s.cost,
    verdict: s.verdict,
  );
}

/// BUY/HOLD/SELL family for a raw rating (collapses the five-tier scale for filtering + pills).
String ratingFamily(String? r) => switch (r?.toLowerCase()) {
      'buy' || 'overweight' => 'Buy',
      'sell' || 'underweight' => 'Sell',
      _ => 'Hold',
    };

/// Launch a run from the current Settings config and jump to the Terminal to watch it.
Future<void> _launch(WidgetRef ref) async {
  final cfg = await ref.read(settingsControllerProvider.notifier).buildLaunchConfig();
  ref.read(appSurfaceProvider.notifier).go(AppSurface.terminal);
  await ref.read(runControllerProvider.notifier).start(config: cfg);
}

/// Re-run a specific ticker: set it as the active ticker, then launch with the current config.
Future<void> _launchTicker(WidgetRef ref, String ticker) async {
  ref.read(settingsControllerProvider.notifier).setTicker(ticker);
  await _launch(ref);
}

/// The Hub: launch a run, track tickers, and browse run history with click-through to a cached review.
class HubSurface extends ConsumerStatefulWidget {
  const HubSurface({super.key});
  @override
  ConsumerState<HubSurface> createState() => _HubSurfaceState();
}

class _HubSurfaceState extends ConsumerState<HubSurface> {
  RunSummary? _reviewing; // non-null => showing the cached review for this run
  String _query = '';
  String? _ratingFilter; // null = all; else Buy | Hold | Sell

  @override
  Widget build(BuildContext context) {
    ref.listen(runControllerProvider, (prev, next) {
      // Launching a run (from the cached review, watchlist, or launch card) drops the open cached
      // review, so returning to the Hub lands on Home — not a stale past run.
      if (next.phase == RunPhase.running && _reviewing != null) {
        setState(() => _reviewing = null);
      }
      // Refresh history when a run finishes (its manifest is persisted before the status flips).
      if (next.isTerminal && prev?.phase != next.phase) {
        ref.invalidate(runHistoryProvider);
      }
    });

    if (_reviewing != null) {
      return _CachedReview(summary: _reviewing!, onBack: () => setState(() => _reviewing = null));
    }

    final history = ref.watch(runHistoryProvider);
    return ColoredBox(
      color: QC.bg,
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),
                  const SizedBox(height: 20),
                  _LaunchCard(onRun: () => _launch(ref)),
                  const SizedBox(height: 16),
                  _WatchlistSection(
                    runs: history.value ?? const [],
                    onRun: (t) => _launchTicker(ref, t),
                  ),
                  const SizedBox(height: 16),
                  _HistorySection(
                    history: history,
                    query: _query,
                    ratingFilter: _ratingFilter,
                    onQuery: (q) => setState(() => _query = q),
                    onRatingFilter: (r) => setState(() => _ratingFilter = r),
                    onRefresh: () => ref.invalidate(runHistoryProvider),
                    onOpen: (r) => setState(() => _reviewing = r),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Header ----------------------------------------------------------------------------------------
class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Hub',
            style: TextStyle(color: QC.textHi, fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(height: 4),
        Text('Launch a run, track tickers, and revisit past verdicts.',
            style: TextStyle(color: QC.textMid, fontSize: 13)),
      ],
    );
  }
}

// --- Launch card -----------------------------------------------------------------------------------
class _LaunchCard extends ConsumerStatefulWidget {
  final Future<void> Function() onRun;
  const _LaunchCard({required this.onRun});
  @override
  ConsumerState<_LaunchCard> createState() => _LaunchCardState();
}

class _LaunchCardState extends ConsumerState<_LaunchCard> {
  late final TextEditingController _ticker =
      TextEditingController(text: ref.read(settingsControllerProvider).ticker);

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// Open the as-of date picker (bounded firstDate..today, so a future date can never be chosen — that
  /// would make FRED leak forward data). Picking today = a live run → clear to null.
  Future<void> _pickDate(BuildContext context, String? current) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _parseIsoDate(current) ?? today,
      firstDate: DateTime(2015),
      lastDate: today,
      helpText: 'As-of date (historical run)',
    );
    if (picked == null || !context.mounted) return;
    final ctrl = ref.read(settingsControllerProvider.notifier);
    ctrl.setTradeDate(_isSameDay(picked, today) ? null : _fmtIsoDate(picked));
  }

  @override
  Widget build(BuildContext context) {
    // Keep the field in sync when the ticker is set elsewhere (a watchlist/history re-run), without
    // clobbering an in-progress edit (during typing, settings.ticker == _ticker.text already).
    ref.listen(settingsControllerProvider.select((s) => s.ticker), (_, t) {
      if (t != _ticker.text) _ticker.text = t;
    });
    final s = ref.watch(settingsControllerProvider);
    final running = ref.watch(runControllerProvider).phase == RunPhase.running;
    final needsProvider = !s.demoMode && s.provider == null;
    // Pre-launch key gate: referenced providers (global ∪ Dream Team) that need a key but have none.
    // Gate Run while the async vault check is still resolving too, so a missing key can never slip
    // through the brief loading window (the notice only shows once we actually have the list).
    final missingAsync = ref.watch(missingKeysProvider);
    final missing = missingAsync.value ?? const <String>[];
    final missingKeys = !s.demoMode && missing.isNotEmpty;
    // P3.2b capability backstop: tool-analyst roles whose EFFECTIVE model is known-non-tool (a discovered
    // local model with no tools, or a bench/global combo the picker never gated) — such a run silently
    // produces empty analyst reports, so refuse it before POST /runs.
    final capViolations = !s.demoMode
        ? (ref.watch(capabilityGateProvider).value ?? const <String>[])
        : const <String>[];
    final capBlocked = capViolations.isNotEmpty;
    final gated = needsProvider ||
        (!s.demoMode && (missingAsync.isLoading || missing.isNotEmpty)) ||
        capBlocked;
    final config = s.demoMode
        ? 'Demo mode · cost-free synthetic run'
        : [
            if (s.provider != null) _providerShort(s.provider!) else 'No provider — set one in Settings',
            if (s.deepModel != null) s.deepModel!,
          ].join(' · ');

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Launch'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 150,
                child: TextField(
                  controller: _ticker,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9.\\-]')),
                    TextInputFormatter.withFunction(
                        (_, n) => n.copyWith(text: n.text.toUpperCase())),
                  ],
                  onChanged: (v) => ref.read(settingsControllerProvider.notifier).setTicker(v),
                  style: const TextStyle(
                      color: QC.textHi, fontSize: 16, fontFamily: QC.fontMono, letterSpacing: 1),
                  decoration: _dec('Ticker'),
                ),
              ),
              const SizedBox(width: 14),
              _AsOfChip(tradeDate: s.tradeDate, onPick: () => _pickDate(context, s.tradeDate)),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(config,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: QC.textLo, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 14),
              FilledButton.icon(
                onPressed: (running || gated) ? null : () => widget.onRun(),
                style: FilledButton.styleFrom(
                    backgroundColor: QC.accent, padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(running ? 'Running…' : 'Run analysis'),
              ),
            ],
          ),
          // P3.5: a past as-of run is historical — warn that live-only sources (Polymarket) can't be
          // time-travelled, so their signals reflect now, not the as-of date. (FRED honours the date.)
          if (s.tradeDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.history_toggle_off, size: 15, color: QC.textLo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Historical as-of run. Prediction-market (Polymarket) signals always reflect live '
                    'markets, not ${s.tradeDate}.',
                    style: const TextStyle(color: QC.textLo, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (missingKeys) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.key_off_outlined, size: 15, color: QC.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: 'Needs keys for: ${missing.map(_providerShort).join(', ')}. ',
                          style: const TextStyle(
                              color: QC.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                      const TextSpan(
                          text: 'Set them in Settings to launch.',
                          style: TextStyle(color: QC.textLo, fontSize: 12)),
                    ]),
                  ),
                ),
              ],
            ),
          ],
          if (capBlocked) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.build_circle_outlined, size: 15, color: QC.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                          text: "No tool support: ${capViolations.join(', ')}. ",
                          style: const TextStyle(
                              color: QC.warning, fontSize: 12, fontWeight: FontWeight.w600)),
                      const TextSpan(
                          text: 'Pick a tool-capable model for these roles in Settings to launch.',
                          style: TextStyle(color: QC.textLo, fontSize: 12)),
                    ]),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// --- As-of date chip -------------------------------------------------------------------------------
DateTime? _parseIsoDate(String? s) {
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String _fmtIsoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// The launch-card date control. "Today" (a live run) when no as-of is set; a warning-tinted
/// "As-of DATE" when a historical date is chosen, so the run's nature is unmistakable before launch.
class _AsOfChip extends StatelessWidget {
  final String? tradeDate;
  final VoidCallback onPick;
  const _AsOfChip({required this.tradeDate, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final historical = tradeDate != null;
    final color = historical ? QC.warning : QC.textMid;
    return OutlinedButton.icon(
      onPressed: onPick,
      icon: Icon(historical ? Icons.history : Icons.today_outlined, size: 15, color: color),
      label: Text(historical ? 'As-of $tradeDate' : 'Today',
          style: TextStyle(color: color, fontSize: 12.5)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: historical ? QC.warning : QC.border),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      ),
    );
  }
}

// --- Watchlist -------------------------------------------------------------------------------------
class _WatchlistSection extends ConsumerStatefulWidget {
  final List<RunSummary> runs;
  final Future<void> Function(String) onRun;
  const _WatchlistSection({required this.runs, required this.onRun});
  @override
  ConsumerState<_WatchlistSection> createState() => _WatchlistSectionState();
}

class _WatchlistSectionState extends ConsumerState<_WatchlistSection> {
  final _add = TextEditingController();
  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  RunSummary? _latestFor(String ticker) {
    for (final r in widget.runs) {
      if (r.ticker == ticker) return r; // history is newest-first
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final watchlist = ref.watch(settingsControllerProvider.select((s) => s.watchlist));
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardLabel('Watchlist'),
          const SizedBox(height: 12),
          if (watchlist.isEmpty)
            const Text('Add tickers to track their latest verdict and re-run in a tap.',
                style: TextStyle(color: QC.textLo, fontSize: 12.5))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in watchlist)
                  _WatchChip(
                    ticker: t,
                    latest: _latestFor(t),
                    onRun: () => widget.onRun(t),
                    onRemove: () => ctrl.removeWatch(t),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _add,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9.\\-]')),
                    TextInputFormatter.withFunction(
                        (_, n) => n.copyWith(text: n.text.toUpperCase())),
                  ],
                  onSubmitted: (_) => _addTicker(ctrl),
                  style: const TextStyle(color: QC.textHi, fontSize: 13, fontFamily: QC.fontMono),
                  decoration: _dec('Add ticker'),
                ),
              ),
              const SizedBox(width: 8),
              _MiniButton(label: 'Add', onTap: () => _addTicker(ctrl)),
            ],
          ),
        ],
      ),
    );
  }

  void _addTicker(SettingsController ctrl) {
    final t = _add.text.trim();
    if (t.isEmpty) return;
    ctrl.addWatch(t); // add-only: re-adding a tracked ticker is a no-op, never a silent removal
    _add.clear();
  }
}

class _WatchChip extends StatelessWidget {
  final String ticker;
  final RunSummary? latest;
  final VoidCallback onRun;
  final VoidCallback onRemove;
  const _WatchChip(
      {required this.ticker, required this.latest, required this.onRun, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: QC.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: QC.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(ticker,
              style: const TextStyle(
                  color: QC.textHi, fontSize: 13, fontFamily: QC.fontMono, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          if (latest?.rating != null) _RatingDot(latest!.rating) else const _RatingDot(null),
          const SizedBox(width: 6),
          _IconBtn(icon: Icons.play_arrow, tooltip: 'Re-run $ticker', onTap: onRun),
          _IconBtn(icon: Icons.close, tooltip: 'Remove', onTap: onRemove),
        ],
      ),
    );
  }
}

// --- History ---------------------------------------------------------------------------------------
class _HistorySection extends StatelessWidget {
  final AsyncValue<List<RunSummary>> history;
  final String query;
  final String? ratingFilter;
  final ValueChanged<String> onQuery;
  final ValueChanged<String?> onRatingFilter;
  final VoidCallback onRefresh;
  final ValueChanged<RunSummary> onOpen;
  const _HistorySection({
    required this.history,
    required this.query,
    required this.ratingFilter,
    required this.onQuery,
    required this.onRatingFilter,
    required this.onRefresh,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _CardLabel('History'),
              const Spacer(),
              _IconBtn(icon: Icons.refresh, tooltip: 'Refresh', onTap: onRefresh),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    onChanged: onQuery,
                    style: const TextStyle(color: QC.textHi, fontSize: 13),
                    decoration: _dec('Filter by ticker').copyWith(
                      prefixIcon: const Icon(Icons.search, size: 16, color: QC.textLo),
                      prefixIconConstraints: const BoxConstraints(minWidth: 34),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              for (final f in const [null, 'Buy', 'Hold', 'Sell'])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _FilterChip(
                    label: f ?? 'All',
                    selected: ratingFilter == f,
                    color: f == null ? QC.accent : ratingColor(f),
                    onTap: () => onRatingFilter(f),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          history.when(
            data: (runs) => _list(runs),
            loading: () => const _Notice(spinner: true, title: 'Loading history…'),
            error: (e, _) =>
                _Notice(title: 'Couldn’t load history', subtitle: '$e', onRetry: onRefresh),
          ),
        ],
      ),
    );
  }

  Widget _list(List<RunSummary> all) {
    final q = query.trim().toUpperCase();
    final runs = all
        .where((r) => q.isEmpty || r.ticker.toUpperCase().contains(q))
        .where((r) => ratingFilter == null || ratingFamily(r.rating) == ratingFilter)
        .toList(growable: false);
    if (all.isEmpty) {
      return const _Notice(title: 'No runs yet', subtitle: 'Launch one above to start your history.');
    }
    if (runs.isEmpty) {
      return const _Notice(title: 'No runs match', subtitle: 'Clear the filters to see all runs.');
    }
    return Column(children: [for (final r in runs) _RunRow(r, onOpen: () => onOpen(r))]);
  }
}

class _RunRow extends ConsumerWidget {
  final RunSummary run;
  final VoidCallback onOpen;
  const _RunRow(this.run, {required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final watched = ref.watch(settingsControllerProvider.select((s) => s.watchlist.contains(run.ticker)));
    final date = run.tradeDate ?? (run.createdAt?.split('T').first ?? '');
    final model = [if (run.provider != null) _providerShort(run.provider!), if (run.deepModel != null) run.deepModel!]
        .join(' · ');
    final cost = run.cost?.estUsd;
    return Semantics(
      button: true,
      container: true,
      label: '${run.ticker} ${ratingFamily(run.rating)} $date ${run.mode}',
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: QC.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: QC.border),
          ),
          child: Row(
            children: [
              SizedBox(width: 64, child: _RatingPill(run.rating)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(run.ticker,
                            style: const TextStyle(
                                color: QC.textHi, fontSize: 14, fontFamily: QC.fontMono, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text(date, style: const TextStyle(color: QC.textMid, fontSize: 12)),
                        if (run.isDemo) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                                color: QC.surface1, borderRadius: BorderRadius.circular(4), border: Border.all(color: QC.border)),
                            child: const Text('DEMO',
                                style: TextStyle(color: QC.textLo, fontSize: 9, letterSpacing: 1, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                    if (model.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(model,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: QC.textLo, fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
              if (cost != null) ...[
                Text('\$${cost.toStringAsFixed(2)}',
                    style: const TextStyle(color: QC.textMid, fontSize: 12, fontFamily: QC.fontMono)),
                const SizedBox(width: 10),
              ],
              _IconBtn(
                icon: watched ? Icons.star : Icons.star_border,
                tooltip: watched ? 'Unwatch' : 'Watch',
                color: watched ? QC.warning : QC.textLo,
                onTap: () => ref.read(settingsControllerProvider.notifier).toggleWatch(run.ticker),
              ),
              const Icon(Icons.chevron_right, size: 18, color: QC.textLo),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Cached review (read-only re-render through TerminalBody) --------------------------------------
class _CachedReview extends ConsumerWidget {
  final RunSummary summary;
  final VoidCallback onBack;
  const _CachedReview({required this.summary, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reports = ref.watch(runReportsProvider(summary.runId));
    return ColoredBox(
      color: QC.bg,
      child: Column(
        children: [
          Container(
            height: 44,
            color: QC.surface1,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _MiniButton(label: '← Back', onTap: onBack),
                const SizedBox(width: 12),
                Text('Cached run · ${summary.ticker}',
                    style: const TextStyle(color: QC.textMid, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1, color: QC.border),
          // The Dream Team "cast list" — what model actually played each role. Self-guards to nothing
          // for demo / pre-P2.5 runs (no resolved map), so those reviews render unchanged.
          _CastListBar(summary: summary),
          Expanded(
            child: reports.when(
              data: (sections) => TerminalBody(
                state: cachedRunState(summary, sections),
                onRun: () => _launchTicker(ref, summary.ticker),
                runLabel: 'Re-run ${summary.ticker}', // a read-only review re-runs, not a fresh launch
              ),
              loading: () => const _Notice(spinner: true, title: 'Loading reports…'),
              error: (e, _) => _Notice(
                  title: 'Couldn’t load this run',
                  subtitle: '$e',
                  onRetry: () => ref.invalidate(runReportsProvider(summary.runId))),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Dream Team cast list (post-run provenance) ----------------------------------------------------

/// Whether a resolved role model was a user OVERRIDE vs the run's quick/deep fallback. A presentational
/// *differs-from-default* heuristic, NOT ground truth: a role pinned to exactly the global model reads
/// as default, and a manifest with null deep/quickModel degrades to a provider-only comparison.
/// (resolve_agent_models flattens override-vs-fallback, so the bit is inferred — never build correctness
/// on it; the c2 gate must not.)
bool _isCastOverride(String roleKey, AgentModel m, RunSummary s) {
  if (m.provider != s.provider) return true;
  final expected = dreamTeamDeepRoles.contains(roleKey) ? s.deepModel : s.quickModel;
  return expected != null && m.model != expected;
}

/// A collapsible "Cast" strip in the cached review: role → the model that actually ran it, grouped by
/// the same 5 stages as the roster. Self-guards to [SizedBox.shrink] when there is no resolved map
/// (demo / pre-P2.5 runs), so those reviews are pixel-identical to before.
class _CastListBar extends StatefulWidget {
  final RunSummary summary;
  const _CastListBar({required this.summary});
  @override
  State<_CastListBar> createState() => _CastListBarState();
}

class _CastListBarState extends State<_CastListBar> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final models = widget.summary.agentModels;
    if (models == null || models.isEmpty) return const SizedBox.shrink();
    final overrides = models.entries.where((e) => _isCastOverride(e.key, e.value, widget.summary)).length;
    return Container(
      color: QC.surface1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.groups_outlined, size: 15, color: QC.textMid),
                  const SizedBox(width: 8),
                  Text('Cast · ${models.length} roles',
                      style: const TextStyle(
                          color: QC.textMid, fontSize: 12, fontWeight: FontWeight.w600)),
                  if (overrides > 0) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: QC.accent.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: QC.accent.withValues(alpha: 0.5)),
                      ),
                      child: Text('$overrides pinned',
                          style: const TextStyle(
                              color: QC.accent, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  const Spacer(),
                  Icon(_open ? Icons.expand_less : Icons.expand_more, size: 18, color: QC.textLo),
                ],
              ),
            ),
          ),
          if (_open) _CastList(summary: widget.summary),
        ],
      ),
    );
  }
}

/// The pure, grouped cast panel (golden/test-friendly). Renders every resolved role under its stage,
/// the model in mono, with an accent "pinned" chip on inferred overrides.
class _CastList extends StatelessWidget {
  final RunSummary summary;
  const _CastList({required this.summary});

  @override
  Widget build(BuildContext context) {
    final models = summary.agentModels ?? const <String, AgentModel>{};
    final children = <Widget>[];
    for (final (stageLabel, keys) in dreamTeamStages) {
      final present = keys.where((k) => models[k] != null).toList(growable: false);
      if (present.isEmpty) continue;
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(stageLabel.toUpperCase(),
            style: const TextStyle(
                color: QC.textLo, fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      ));
      for (final role in present) {
        children.add(_CastRow(
          roleKey: role,
          model: models[role]!,
          isOverride: _isCastOverride(role, models[role]!, summary),
        ));
      }
    }
    return Container(
      width: double.infinity,
      color: QC.surface1,
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

class _CastRow extends StatelessWidget {
  final String roleKey;
  final AgentModel model;
  final bool isOverride;
  const _CastRow({required this.roleKey, required this.model, required this.isOverride});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(dreamTeamRoleLabel(roleKey),
                style: const TextStyle(color: QC.textMid, fontSize: 12)),
          ),
          if (isOverride) ...[
            const Icon(Icons.push_pin, size: 11, color: QC.accent),
            const SizedBox(width: 5),
          ],
          Flexible(
            child: Text('${_providerShort(model.provider)} · ${model.model}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                    color: isOverride ? QC.textHi : QC.textLo,
                    fontSize: 12,
                    fontFamily: QC.fontMono,
                    fontWeight: isOverride ? FontWeight.w600 : FontWeight.w400)),
          ),
        ],
      ),
    );
  }
}

// --- Shared bits -----------------------------------------------------------------------------------
String _providerShort(String p) => switch (p) {
      'google' => 'Google',
      'openai' => 'OpenAI',
      'anthropic' => 'Anthropic',
      'openai_compatible' => 'OpenAI-compat',
      _ => p,
    };

InputDecoration _dec(String hint) => InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: QC.surface2,
      hintText: hint,
      hintStyle: const TextStyle(color: QC.textLo, fontSize: 13),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: QC.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: QC.accent)),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: QC.border)),
    );

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          color: QC.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QC.border),
        ),
        child: child,
      );
}

class _CardLabel extends StatelessWidget {
  final String text;
  const _CardLabel(this.text);
  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(),
      style: const TextStyle(
          color: QC.textMid, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8));
}

class _RatingPill extends StatelessWidget {
  final String? rating;
  const _RatingPill(this.rating);
  @override
  Widget build(BuildContext context) {
    final c = ratingColor(rating);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Text((rating == null ? '—' : ratingFamily(rating)).toUpperCase(),
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
    );
  }
}

class _RatingDot extends StatelessWidget {
  final String? rating;
  const _RatingDot(this.rating);
  @override
  Widget build(BuildContext context) {
    final c = rating == null ? QC.textLo : ratingColor(rating);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.circle, size: 7, color: c),
      const SizedBox(width: 4),
      Text(rating == null ? '—' : ratingFamily(rating),
          style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.16) : QC.surface2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? color : QC.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: selected ? QC.textHi : QC.textMid,
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
        ),
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _MiniButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: QC.border),
          ),
          child: Text(label,
              style: const TextStyle(color: QC.textHi, fontSize: 12.5, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color color;
  const _IconBtn({required this.icon, required this.tooltip, required this.onTap, this.color = QC.textMid});
  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 16, color: color),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      padding: EdgeInsets.zero,
      onPressed: onTap,
    );
  }
}

class _Notice extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool spinner;
  final VoidCallback? onRetry;
  const _Notice({required this.title, this.subtitle, this.spinner = false, this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (spinner)
              const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: QC.accent))
            else
              const Icon(Icons.inbox_outlined, size: 26, color: QC.textLo),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(color: QC.textHi, fontSize: 14, fontWeight: FontWeight.w600)),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: QC.textLo, fontSize: 12)),
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              _MiniButton(label: 'Retry', onTap: onRetry!),
            ],
          ],
        ),
      ),
    );
  }
}
