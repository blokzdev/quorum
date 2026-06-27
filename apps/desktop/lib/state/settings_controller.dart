import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart' show dreamTeamRoleKeys;
import '../services/key_vault.dart';

/// The persisted model-config subset of [SettingsState] — a named, reusable "Bench" (preset) the user
/// can save and re-apply. Deliberately excludes API keys (those live in the OS vault, never on disk),
/// the `demoMode` toggle, and the ticker (a per-run input, not a saved model profile).
class Bench {
  final String name;
  final String? provider;
  final String? deepModel;
  final String? quickModel;
  final String? customDeepModel;
  final String? customQuickModel;

  /// The single effort/thinking value for the chosen provider (mapped to the right knob at launch).
  final String? effort;
  final String? backendUrl;
  final int researchDepth;

  /// Per-role "Dream Team" lineup saved with this preset (role_key -> AgentModel), if any.
  final Map<String, AgentModel>? agentModels;

  const Bench({
    required this.name,
    this.provider,
    this.deepModel,
    this.quickModel,
    this.customDeepModel,
    this.customQuickModel,
    this.effort,
    this.backendUrl,
    this.researchDepth = 1,
    this.agentModels,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        if (provider != null) 'provider': provider,
        if (deepModel != null) 'deep_model': deepModel,
        if (quickModel != null) 'quick_model': quickModel,
        if (customDeepModel != null) 'custom_deep_model': customDeepModel,
        if (customQuickModel != null) 'custom_quick_model': customQuickModel,
        if (effort != null) 'effort': effort,
        if (backendUrl != null) 'backend_url': backendUrl,
        'research_depth': researchDepth,
        'agent_models': ?agentModelsToJson(agentModels),
      };

  factory Bench.fromJson(Map<String, dynamic> j) => Bench(
        name: j['name'] as String? ?? '',
        provider: j['provider'] as String?,
        deepModel: j['deep_model'] as String?,
        quickModel: j['quick_model'] as String?,
        customDeepModel: j['custom_deep_model'] as String?,
        customQuickModel: j['custom_quick_model'] as String?,
        effort: j['effort'] as String?,
        backendUrl: j['backend_url'] as String?,
        researchDepth: (j['research_depth'] as num?)?.toInt() ?? 1,
        agentModels: agentModelsFromJson(j['agent_models']),
      );
}

/// All durable, non-secret desktop settings: the chosen model config (provider / quick+deep model /
/// effort / endpoint), run defaults (ticker / research depth / analysts / language), saved Benches,
/// and the one-time `.env` seed flag. **Never holds API keys** — keys live only in the OS keystore
/// ([KeyVault]); this object is what gets written to `settings.json`.
class SettingsState {
  /// Cost-free synthetic run when true (the safe default so a fresh install never spends). When false,
  /// [buildLaunchConfig] assembles a real `pro` run and merges the chosen provider's vault key.
  final bool demoMode;
  final String ticker;
  final String? provider;
  final String? deepModel;
  final String? quickModel;
  final String? customDeepModel;
  final String? customQuickModel;
  final String? effort;
  final String? backendUrl;
  final int researchDepth;
  final List<String>? analysts;
  final String outputLanguage;
  final List<Bench> benches;

  /// Tickers the user tracks on the Hub (uppercased). A run-level list, not part of a [Bench] preset.
  final List<String> watchlist;

  /// "Dream Team" per-role model overrides (role_key -> AgentModel); null = the quick/deep split runs
  /// every role. Independent of the global provider, so [withProvider] does NOT clear it.
  final Map<String, AgentModel>? agentModels;

  /// Idempotency latch for the first-launch `.env` → vault import (see [maybeSeedKeysFromEnv]).
  final bool seededFromEnv;

  const SettingsState({
    this.demoMode = true,
    this.ticker = 'NVDA',
    this.provider,
    this.deepModel,
    this.quickModel,
    this.customDeepModel,
    this.customQuickModel,
    this.effort,
    this.backendUrl,
    this.researchDepth = 1,
    this.analysts,
    this.outputLanguage = 'English',
    this.benches = const [],
    this.watchlist = const [],
    this.agentModels,
    this.seededFromEnv = false,
  });

  SettingsState copyWith({
    bool? demoMode,
    String? ticker,
    String? provider,
    String? deepModel,
    String? quickModel,
    String? customDeepModel,
    String? customQuickModel,
    String? effort,
    String? backendUrl,
    int? researchDepth,
    List<String>? analysts,
    String? outputLanguage,
    List<Bench>? benches,
    List<String>? watchlist,
    Map<String, AgentModel>? agentModels,
    bool? seededFromEnv,
  }) {
    return SettingsState(
      demoMode: demoMode ?? this.demoMode,
      ticker: ticker ?? this.ticker,
      provider: provider ?? this.provider,
      deepModel: deepModel ?? this.deepModel,
      quickModel: quickModel ?? this.quickModel,
      customDeepModel: customDeepModel ?? this.customDeepModel,
      customQuickModel: customQuickModel ?? this.customQuickModel,
      effort: effort ?? this.effort,
      backendUrl: backendUrl ?? this.backendUrl,
      researchDepth: researchDepth ?? this.researchDepth,
      analysts: analysts ?? this.analysts,
      outputLanguage: outputLanguage ?? this.outputLanguage,
      benches: benches ?? this.benches,
      watchlist: watchlist ?? this.watchlist,
      agentModels: agentModels ?? this.agentModels,
      seededFromEnv: seededFromEnv ?? this.seededFromEnv,
    );
  }

  /// copyWith can't set a field back to null (the `?? this.x` swallows it). Provider changes must clear
  /// the now-invalid model/effort/endpoint selections, so this is the explicit "reset on provider"
  /// transition.
  SettingsState withProvider(String? newProvider) => SettingsState(
        demoMode: demoMode,
        ticker: ticker,
        provider: newProvider,
        deepModel: null,
        quickModel: null,
        customDeepModel: null,
        customQuickModel: null,
        effort: null,
        backendUrl: null,
        researchDepth: researchDepth,
        analysts: analysts,
        outputLanguage: outputLanguage,
        benches: benches,
        watchlist: watchlist,
        agentModels: agentModels, // per-role choices are independent of the global provider
        seededFromEnv: seededFromEnv,
      );

  /// copyWith can't set [agentModels] back to null (the `?? this.x` swallows it). This explicit setter
  /// (used by clear / Bench-apply) can clear the lineup.
  SettingsState withAgentModels(Map<String, AgentModel>? value) => SettingsState(
        demoMode: demoMode,
        ticker: ticker,
        provider: provider,
        deepModel: deepModel,
        quickModel: quickModel,
        customDeepModel: customDeepModel,
        customQuickModel: customQuickModel,
        effort: effort,
        backendUrl: backendUrl,
        researchDepth: researchDepth,
        analysts: analysts,
        outputLanguage: outputLanguage,
        benches: benches,
        watchlist: watchlist,
        agentModels: value,
        seededFromEnv: seededFromEnv,
      );

  Map<String, dynamic> toJson() => {
        'demo_mode': demoMode,
        'ticker': ticker,
        if (provider != null) 'provider': provider,
        if (deepModel != null) 'deep_model': deepModel,
        if (quickModel != null) 'quick_model': quickModel,
        if (customDeepModel != null) 'custom_deep_model': customDeepModel,
        if (customQuickModel != null) 'custom_quick_model': customQuickModel,
        if (effort != null) 'effort': effort,
        if (backendUrl != null) 'backend_url': backendUrl,
        'research_depth': researchDepth,
        if (analysts != null) 'analysts': analysts,
        'output_language': outputLanguage,
        'benches': benches.map((b) => b.toJson()).toList(growable: false),
        'watchlist': watchlist,
        'agent_models': ?agentModelsToJson(agentModels),
        'seeded_from_env': seededFromEnv,
      };

  factory SettingsState.fromJson(Map<String, dynamic> j) => SettingsState(
        demoMode: j['demo_mode'] as bool? ?? true,
        ticker: j['ticker'] as String? ?? 'NVDA',
        provider: j['provider'] as String?,
        deepModel: j['deep_model'] as String?,
        quickModel: j['quick_model'] as String?,
        customDeepModel: j['custom_deep_model'] as String?,
        customQuickModel: j['custom_quick_model'] as String?,
        effort: j['effort'] as String?,
        backendUrl: j['backend_url'] as String?,
        researchDepth: (j['research_depth'] as num?)?.toInt() ?? 1,
        analysts: (j['analysts'] as List?)?.map((e) => e as String).toList(growable: false),
        outputLanguage: j['output_language'] as String? ?? 'English',
        benches: ((j['benches'] as List?) ?? const [])
            .map((b) => Bench.fromJson((b as Map).cast<String, dynamic>()))
            .toList(growable: false),
        watchlist:
            ((j['watchlist'] as List?) ?? const []).map((e) => e as String).toList(growable: false),
        agentModels: agentModelsFromJson(j['agent_models']),
        seededFromEnv: j['seeded_from_env'] as bool? ?? false,
      );

  /// The Bench (model-config snapshot) for the current selection, under [name].
  Bench toBench(String name) => Bench(
        name: name,
        provider: provider,
        deepModel: deepModel,
        quickModel: quickModel,
        customDeepModel: customDeepModel,
        customQuickModel: customQuickModel,
        effort: effort,
        backendUrl: backendUrl,
        researchDepth: researchDepth,
        agentModels: agentModels,
      );
}

/// Reads/writes `settings.json` under the OS app-support dir (`getApplicationSupportDirectory`). All
/// I/O is best-effort: a missing or corrupt file yields defaults, and a write failure never throws —
/// settings are a convenience, never load-bearing for a run.
class SettingsStore {
  static const _fileName = 'settings.json';

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<SettingsState> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return const SettingsState();
      final raw = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return SettingsState.fromJson(raw);
    } catch (_) {
      return const SettingsState();
    }
  }

  static Future<void> save(SettingsState s) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(s.toJson()));
    } catch (_) {/* best-effort: never fail a settings mutation on disk I/O */}
  }
}

/// The settings loaded at boot. `main()` overrides this with `SettingsStore.load()`'s result so the
/// controller starts from disk; tests override it with a known state. Default = first-run defaults.
final initialSettingsProvider = Provider<SettingsState>((ref) => const SettingsState());

/// Holds [SettingsState], persists every mutation, and assembles the launch [RunConfig] (merging the
/// chosen provider's key from the vault for real runs). The single source of truth Model Studio binds
/// to and the Terminal launches from.
final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(SettingsController.new);

/// Monotonic counter bumped on every vault key write/delete (including the one-time `.env` seed and
/// Forget-all-keys). Widgets that display whether a provider key is stored watch this and re-check the
/// vault when it changes — the OS keystore itself emits no change notification.
final keyVaultRevisionProvider = NotifierProvider<KeyVaultRevision, int>(KeyVaultRevision.new);

class KeyVaultRevision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state = state + 1;
}

class SettingsController extends Notifier<SettingsState> {
  @override
  SettingsState build() => ref.read(initialSettingsProvider);

  KeyVault get _vault => ref.read(keyVaultProvider);

  void _set(SettingsState next) {
    state = next;
    SettingsStore.save(next); // fire-and-forget; save() swallows I/O errors
  }

  void setDemoMode(bool v) => _set(state.copyWith(demoMode: v));
  void setTicker(String v) => _set(state.copyWith(ticker: v.trim().toUpperCase()));
  void setProvider(String? v) => _set(state.withProvider(v)); // clears stale model/effort/endpoint
  void setDeepModel(String? v) => _set(state.copyWith(deepModel: v));
  void setQuickModel(String? v) => _set(state.copyWith(quickModel: v));
  void setCustomDeepModel(String? v) => _set(state.copyWith(customDeepModel: v));
  void setCustomQuickModel(String? v) => _set(state.copyWith(customQuickModel: v));
  void setEffort(String? v) => _set(state.copyWith(effort: v));
  void setBackendUrl(String? v) => _set(state.copyWith(backendUrl: v));
  void setResearchDepth(int v) => _set(state.copyWith(researchDepth: v.clamp(1, 5)));
  void setAnalysts(List<String>? v) => _set(state.copyWith(analysts: v));
  void setOutputLanguage(String v) => _set(state.copyWith(outputLanguage: v));

  // --- Benches (saved model-config presets) --------------------------------------------------------
  void saveBench(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = [...state.benches.where((b) => b.name != trimmed), state.toBench(trimmed)];
    _set(state.copyWith(benches: next));
  }

  void applyBench(Bench b) => _set(state
      .copyWith(
        provider: b.provider,
        deepModel: b.deepModel,
        quickModel: b.quickModel,
        customDeepModel: b.customDeepModel,
        customQuickModel: b.customQuickModel,
        effort: b.effort,
        backendUrl: b.backendUrl,
        researchDepth: b.researchDepth,
      )
      // Explicit so a bench with no lineup CLEARS the current one (copyWith can't null it).
      .withAgentModels(b.agentModels));

  void deleteBench(String name) =>
      _set(state.copyWith(benches: state.benches.where((b) => b.name != name).toList()));

  // --- Dream Team (per-role model overrides) -------------------------------------------------------
  /// Assign (or, with a null [model], unassign) a role's model. A blank-model [model] also unassigns —
  /// defense in depth behind the picker's transient-edit discipline, so an `AgentModel(model: '')` can
  /// never persist (the engine and the manifest both silently drop a blank-model spec, which would make
  /// the roster claim a role is assigned while the run uses the fallback). An empty map collapses to
  /// null so an unused lineup is omitted on the wire and from settings.json.
  void setAgentModel(String role, AgentModel? model) {
    final next = {...?state.agentModels};
    if (model == null || model.model.trim().isEmpty) {
      next.remove(role);
    } else {
      next[role] = model;
    }
    _set(state.withAgentModels(next.isEmpty ? null : next));
  }

  /// Pin [model] to all 12 Dream Team roles in one write (apply-to-all). A blank-model [model] is a
  /// no-op (same invariant as [setAgentModel]).
  void setAllAgentModels(AgentModel model) {
    if (model.model.trim().isEmpty) return;
    _set(state.withAgentModels({for (final role in dreamTeamRoleKeys) role: model}));
  }

  void clearAgentModels() => _set(state.withAgentModels(null));

  // --- Watchlist (tracked tickers on the Hub) ------------------------------------------------------
  /// Add-only: a no-op if already tracked. (The star/row affordance uses [toggleWatch] to flip.)
  void addWatch(String ticker) {
    final t = ticker.trim().toUpperCase();
    if (t.isEmpty || state.watchlist.contains(t)) return;
    _set(state.copyWith(watchlist: [...state.watchlist, t]));
  }

  void toggleWatch(String ticker) {
    final t = ticker.trim().toUpperCase();
    if (t.isEmpty) return;
    final next = state.watchlist.contains(t)
        ? state.watchlist.where((w) => w != t).toList()
        : [...state.watchlist, t];
    _set(state.copyWith(watchlist: next));
  }

  void removeWatch(String ticker) => _set(
      state.copyWith(watchlist: state.watchlist.where((w) => w != ticker).toList()));

  // --- Keys (OS vault; never persisted to settings.json) -------------------------------------------
  // Each mutation bumps keyVaultRevisionProvider so any widget showing whether a key is stored can
  // re-check the vault (the vault has no change notification of its own).
  void _bumpKeys() => ref.read(keyVaultRevisionProvider.notifier).bump();

  Future<void> saveKey(String provider, String key) async {
    await _vault.write(provider, key);
    _bumpKeys();
  }

  Future<void> deleteKey(String provider) async {
    await _vault.delete(provider);
    _bumpKeys();
  }

  Future<String?> readKey(String provider) => _vault.read(provider);
  Future<bool> hasKey(String provider) async => (await _vault.read(provider))?.isNotEmpty ?? false;

  Future<void> forgetAllKeys() async {
    await _vault.forgetAll();
    _bumpKeys();
  }

  /// One-time import of provider keys from the sidecar host's gitignored `.env` into the OS vault, so a
  /// developer/user with keys already in `.env` doesn't have to re-type them. Idempotent via
  /// [SettingsState.seededFromEnv]; best-effort (a fetch failure just leaves the latch unset to retry).
  /// [fetchEnvKeys] is injected (the caller passes `() => apiClient.envKeys()`) so this stays testable
  /// without a live sidecar.
  ///
  /// Note: the shared Gemini test key currently in `.env` is intentionally NOT skiplisted here — on a
  /// single-user desktop, importing the user's own `.env` keys is the whole point, and the shared-key
  /// rotation is tracked as a Phase 3 release-hygiene task (a stale vault key simply fails auth and is
  /// re-entered in Model Studio).
  Future<void> maybeSeedKeysFromEnv(Future<Map<String, dynamic>> Function() fetchEnvKeys) async {
    if (state.seededFromEnv) return;
    try {
      final envKeys = await fetchEnvKeys();
      for (final e in envKeys.entries) {
        final key = e.value;
        if (key is String && key.isNotEmpty) {
          await _vault.write(e.key, key);
        }
      }
      _bumpKeys(); // let any open Model Studio key field refresh its "Stored" badge
      _set(state.copyWith(seededFromEnv: true));
    } catch (_) {
      // Leave seededFromEnv false so a later attempt (e.g. once the sidecar is up) can retry.
    }
  }

  // --- Launch config ------------------------------------------------------------------------------
  String? _resolved(String? selected, String? custom) {
    if (selected == 'custom') {
      final c = custom?.trim();
      return (c != null && c.isNotEmpty) ? c : null;
    }
    return selected;
  }

  /// Assemble the `POST /runs` config from the current settings. Demo mode returns the cost-free
  /// synthetic config (no keys — the sidecar strips them anyway). A real run is `mode: 'pro'` with the
  /// resolved models, the provider-matched effort knob, optional endpoint, and the chosen provider's
  /// key merged from the vault (only when a key exists; ollama/keyless local servers send none).
  Future<RunConfig> buildLaunchConfig() async {
    final s = state;
    final ticker = s.ticker.trim().isEmpty ? 'NVDA' : s.ticker.trim().toUpperCase();
    if (s.demoMode) {
      return RunConfig(mode: 'demo', ticker: ticker, stepDelay: 0.2);
    }

    final provider = s.provider;
    // Merge vault keys for EVERY provider this run references — the global quick/deep provider plus
    // every per-role (Dream Team) provider — so a multi-provider run injects all the keys it needs
    // (the sidecar's JobIsolationContext installs them all). A provider with no stored key is omitted
    // (ollama / keyless local servers send none).
    final providers = <String>{
      ?provider,
      ...?s.agentModels?.values.map((m) => m.provider),
    };
    final merged = <String, String>{};
    for (final p in providers) {
      final key = await _vault.read(p);
      if (key != null && key.isNotEmpty) merged[p] = key;
    }
    final backendUrl = s.backendUrl?.trim();

    return RunConfig(
      mode: 'pro',
      ticker: ticker,
      provider: provider,
      deepModel: _resolved(s.deepModel, s.customDeepModel),
      quickModel: _resolved(s.quickModel, s.customQuickModel),
      backendUrl: (backendUrl != null && backendUrl.isNotEmpty) ? backendUrl : null,
      researchDepth: s.researchDepth,
      analysts: s.analysts,
      outputLanguage: s.outputLanguage,
      // Only the knob for the chosen (global) provider is set; per-role effort rides in agentModels.
      googleThinkingLevel: provider == 'google' ? s.effort : null,
      openaiReasoningEffort: provider == 'openai' ? s.effort : null,
      anthropicEffort: provider == 'anthropic' ? s.effort : null,
      apiKeys: merged.isEmpty ? null : merged,
      agentModels: s.agentModels,
    );
  }
}
