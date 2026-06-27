import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quorum_core/quorum_core.dart';

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

  void applyBench(Bench b) => _set(state.copyWith(
        provider: b.provider,
        deepModel: b.deepModel,
        quickModel: b.quickModel,
        customDeepModel: b.customDeepModel,
        customQuickModel: b.customQuickModel,
        effort: b.effort,
        backendUrl: b.backendUrl,
        researchDepth: b.researchDepth,
      ));

  void deleteBench(String name) =>
      _set(state.copyWith(benches: state.benches.where((b) => b.name != name).toList()));

  // --- Watchlist (tracked tickers on the Hub) ------------------------------------------------------
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
    Map<String, String>? apiKeys;
    if (provider != null) {
      final key = await _vault.read(provider);
      if (key != null && key.isNotEmpty) apiKeys = {provider: key};
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
      // Only the knob for the chosen provider is set; the others stay null and are omitted on the wire.
      googleThinkingLevel: provider == 'google' ? s.effort : null,
      openaiReasoningEffort: provider == 'openai' ? s.effort : null,
      anthropicEffort: provider == 'anthropic' ? s.effort : null,
      apiKeys: apiKeys,
    );
  }
}
