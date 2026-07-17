import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart';
import '../provider_meta.dart'; // providerNeedsKey (+ the shared provider->key-env mirror)
import '../vendor_meta.dart' show macroVendor; // data-vendor key metadata (mirrors VENDOR_API_KEY_ENV)
import 'contrast.dart' show accessibleTint;
import 'focusable.dart';
import '../state/catalog_provider.dart'; // catalogProvider, engineConnectionProvider
import '../state/device_ram_provider.dart'; // deviceRamMbProvider (P5.1b)
import '../state/pull_controller.dart'; // pullControllerProvider (P5.2)
import '../state/run_controller.dart' show httpClientProvider;
import '../state/settings_controller.dart';
import 'brand.dart';

// --- Engine contract mirrors -----------------------------------------------------------------------
// The desktop can't import the Python maps and the catalog endpoint doesn't carry them, so these are
// hand-kept in sync with the engine. Each has a pointer to its source of truth. (The provider->key-env
// map moved to provider_meta.dart so the Hub key gate shares it.)

/// Providers exposing an effort/thinking knob, with the field label and allowed values. Only these
/// three are offered — `buildLaunchConfig` maps the chosen value onto the matching RunConfig knob
/// (`google_thinking_level` / `openai_reasoning_effort` / `anthropic_effort`). Mirrors the engine's
/// per-provider effort handling; clients ignore an effort a model doesn't support.
const _effortSpec = <String, (String, List<String>)>{
  'google': ('Thinking level', ['minimal', 'low', 'medium', 'high']),
  'openai': ('Reasoning effort', ['low', 'medium', 'high']),
  'anthropic': ('Effort', ['low', 'medium', 'high']),
};

/// Only `openai_compatible` (engine `require_base_url=True`) and `ollama` (configurable local default)
/// take a user-supplied OpenAI-compatible base URL; every other provider has a baked-in endpoint in
/// the engine's ProviderSpec. See `tradingagents/llm_clients/openai_client.py`.
const _ollamaDefaultBackendUrl = 'http://localhost:11434/v1';
bool _usesBackendUrl(String provider) => provider == 'openai_compatible' || provider == 'ollama';
bool _requiresBackendUrl(String provider) => provider == 'openai_compatible';

/// Friendly provider labels for the dropdown (the catalog keys are terse ids).
const _providerLabels = <String, String>{
  'openai': 'OpenAI',
  'anthropic': 'Anthropic',
  'google': 'Google Gemini',
  'xai': 'xAI (Grok)',
  'deepseek': 'DeepSeek',
  'qwen': 'Qwen (International)',
  'qwen-cn': 'Qwen (China)',
  'glm': 'GLM · Z.AI',
  'glm-cn': 'GLM · BigModel (China)',
  'minimax': 'MiniMax',
  'minimax-cn': 'MiniMax (China)',
  'ollama': 'Ollama (local)',
  'openai_compatible': 'OpenAI-compatible',
  'mistral': 'Mistral',
  'kimi': 'Kimi · Moonshot',
  'groq': 'Groq',
  'nvidia': 'NVIDIA NIM',
  'bedrock': 'AWS Bedrock',
};
String _providerLabel(String p) => _providerLabels[p] ?? p;

// --- Dream Team (per-role) helpers -----------------------------------------------------------------

/// Providers offerable per role. Excludes ONLY `openai_compatible` — it has `require_base_url=True`
/// engine-side (openai_client.py) and c1 has no per-role base-URL field, so a per-role
/// `openai_compatible` with no URL is a guaranteed broken run. `ollama` is INTENTIONALLY kept: its
/// ProviderSpec bakes in `http://localhost:11434/v1`, so a per-role Ollama resolves that default even
/// when the global provider differs (verified openai_client.py base_url precedence) — the flagship
/// "cheap local analyst + strong cloud judge" lineup. A per-role base-URL field is backlog (P2.5c2+).
List<String> _rosterProviders(Catalog c) =>
    c.providerNames.where((p) => p != 'openai_compatible').toList(growable: false);

/// P3.2: the Ollama picker replaces its static curated guesses with the DEVICE's DISCOVERED models
/// (real `toolCapable`) once discovery succeeds — those are ground truth for what's installed. A `custom`
/// sentinel always trails so a hand-typed id stays possible. Non-Ollama providers (and Ollama before
/// discovery loads / when Ollama is down) keep [base] unchanged, so the picker never regresses.
List<ModelOption> _foldLocalModels(
    String? provider, List<ModelOption> base, List<LocalModel> localModels) {
  if (provider != 'ollama' || localModels.isEmpty) return base;
  final seen = <String>{};
  final out = <ModelOption>[];
  for (final m in localModels) {
    if (seen.add(m.name)) out.add(m.toOption());
  }
  if (seen.add('custom')) out.add(const ModelOption('Custom model id…', 'custom'));
  return out;
}

/// A role's full model set = the dedup-by-value union of the provider's quick + deep options, plus
/// exactly one trailing `custom` sentinel (deduped, so a catalog that already lists `custom` doesn't
/// double it). Prevents DropdownButton duplicate-value asserts when a model appears in both tiers. For
/// Ollama, discovered local models (P3.2) replace the static list — so the gate sees their real capability.
List<ModelOption> _unionModels(Catalog c, String provider, List<LocalModel> localModels) {
  final seen = <String>{};
  final out = <ModelOption>[];
  for (final o in [...c.optionsFor(provider, 'quick'), ...c.optionsFor(provider, 'deep')]) {
    if (seen.add(o.value)) out.add(o);
  }
  if (seen.add('custom')) out.add(const ModelOption('Custom model id…', 'custom'));
  return _foldLocalModels(provider, out, localModels);
}

/// A role is *assigned* iff it carries a provider AND a non-blank model. The single predicate the wire
/// commit, the chip, and the count all share — so the UI can never read "assigned" while the engine
/// (which drops a blank-model spec) runs the fallback.
bool _roleAssigned(AgentModel? m) => m != null && m.model.trim().isNotEmpty;

/// The gate's capability lookup — delegates to the shared [toolCapabilityOf] (quorum_core) so the picker
/// gate and the launch-time backstop can never disagree. null = UNKNOWN → WARNS, never blocks. For
/// Ollama this reads the DISCOVERED model's real capability, so a device's non-tool model (e.g. a plain
/// llama3 8B) is correctly blocked on tool roles.
bool? _toolCapableOf(Catalog catalog, String? provider, String? model, List<LocalModel> localModels) =>
    toolCapabilityOf(catalog, provider, model, localModels);

enum _GateOutcome { ok, warn, block }

/// The capability verdict for a (role gate class, model's tool_capable). The BLOCK condition is
/// EXACTLY `toolCapable == false` — never `!= true` — so a custom/unknown (null) model on a tool role
/// WARNS rather than blocking (which would kill the legitimate cheap-local-analyst lineup).
_GateOutcome _gateOutcome(RoleGate gate, bool? toolCapable) {
  switch (gate) {
    case RoleGate.block:
      if (toolCapable == false) return _GateOutcome.block;
      if (toolCapable == null) return _GateOutcome.warn; // unknown/custom on a tool role
      return _GateOutcome.ok;
    case RoleGate.warn:
      // Structured roles warn only on a KNOWN non-tool model; an unknown/custom (null) one is fine —
      // structured-output support is a different capability than tool-calling.
      if (toolCapable == false) return _GateOutcome.warn; // structured degrades to free-text
      return _GateOutcome.ok;
    case RoleGate.none:
      return _GateOutcome.ok;
  }
}

const _languages = ['English', 'Spanish', 'Chinese', 'Japanese', 'German', 'French', 'Korean'];

/// The Settings surface: resolves the provider/model [catalogProvider] (loading / error+Retry / empty
/// states) and, once the sidecar is reachable, runs the one-time `.env` -> OS-vault key import. The
/// resolved catalog is handed to the pure [SettingsBody] so the golden harness can pump the form
/// hermetically (no live sidecar), mirroring the TerminalSurface/TerminalBody split.
class SettingsSurface extends ConsumerStatefulWidget {
  const SettingsSurface({super.key});
  @override
  ConsumerState<SettingsSurface> createState() => _SettingsSurfaceState();
}

class _SettingsSurfaceState extends ConsumerState<SettingsSurface> {
  @override
  void initState() {
    super.initState();
    // Best-effort, idempotent (seededFromEnv latch). Deferred a frame so the first build paints first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _seedKeysFromEnv());
  }

  Future<void> _seedKeysFromEnv() async {
    try {
      final conn = await ref.read(engineConnectionProvider.future);
      // Reuse the shared http client (do NOT close this ApiClient — httpClientProvider owns the client).
      final api = ApiClient(conn, client: ref.read(httpClientProvider));
      await ref.read(settingsControllerProvider.notifier).maybeSeedKeysFromEnv(api.envKeys);
    } catch (_) {
      // Sidecar not up yet, or no .env keys — leave the latch unset so a later entry can retry.
    }
  }

  void _retry() {
    // The endpoint memoizes its connection, so a stale/broken one must be invalidated alongside the
    // catalog (this is the C7 TODO made concrete for the Settings retry path).
    ref.invalidate(engineConnectionProvider);
    ref.invalidate(catalogProvider);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final catalog = ref.watch(catalogProvider);
    // The vendor catalog is a progressive enhancement: if it hasn't loaded (or failed), the Data
    // sources section simply stays hidden rather than blocking the whole screen. Resolved to a plain
    // value here so SettingsBody stays async-free (the golden target).
    final vendorCatalog =
        ref.watch(vendorCatalogProvider).maybeWhen(data: (v) => v, orElse: () => null);
    // Discovered local models — likewise a progressive enhancement; empty until loaded / if Ollama is
    // down, so the picker keeps its static Ollama option.
    final localModels =
        ref.watch(localModelsProvider).maybeWhen(data: (m) => m, orElse: () => const <LocalModel>[]);
    // The curated Draft Board catalog + the device's RAM (P5.1d) — both progressive enhancements,
    // resolved to plain values so SettingsBody stays async-free (the golden target). An empty-tiers
    // catalog (provider degraded) hides the section exactly like a null vendorCatalog hides Data sources.
    final edgeCatalog =
        ref.watch(edgeModelCatalogProvider).maybeWhen(data: (e) => e, orElse: () => null);
    final deviceRamMb = ref.watch(deviceRamMbProvider).maybeWhen(data: (r) => r, orElse: () => null);
    return Container(
      color: brand.bg,
      child: catalog.when(
        data: (c) => c.providers.isEmpty
            ? _CenterNotice(
                title: 'No providers available',
                subtitle: 'The engine returned an empty catalog.',
                onRetry: _retry)
            : SettingsBody(
                catalog: c,
                vendorCatalog: vendorCatalog,
                localModels: localModels,
                edgeCatalog: edgeCatalog,
                deviceRamMb: deviceRamMb),
        loading: () =>
            const _CenterNotice(title: 'Connecting to the engine…', spinner: true),
        error: (e, _) => _CenterNotice(
            title: 'Couldn’t load the model catalog', subtitle: '$e', onRetry: _retry),
      ),
    );
  }
}

/// The pure, scrollable Model Studio form. Binds to [settingsControllerProvider] and renders against a
/// fixed [catalog], so it has no async dependencies — the golden target.
class SettingsBody extends ConsumerWidget {
  final Catalog catalog;

  /// Golden/test seam: force the (otherwise collapsed-by-default) Dream Team roster open so the
  /// all-default state is render-to-PNG testable. Production never sets it; a configured roster
  /// (non-null agentModels) auto-expands regardless.
  final bool forceExpandDreamTeam;

  /// The per-category data-vendor catalog (`GET /catalog/vendors`, P3.1). Null → the Data sources
  /// section is hidden (catalog not yet loaded / unavailable); the rest of Settings is unaffected.
  final VendorCatalog? vendorCatalog;

  /// The device's discovered Ollama models (`GET /catalog/local-models`, P3.2). Empty → the Ollama
  /// picker keeps its static list + custom-id path (discovery not loaded / Ollama down); non-empty →
  /// real installed models replace the static guesses, each carrying its true tool-capability.
  final List<LocalModel> localModels;

  /// The curated Edge Model Draft Board (`GET /catalog/edge-models`, P5.1d). Null or empty-tiers →
  /// the Draft Board section is hidden (not loaded / provider degraded); the rest is unaffected.
  final EdgeModelCatalog? edgeCatalog;

  /// The device's reported RAM in MiB (P5.1b). Null → fit badges + the tier highlight are suppressed
  /// (no RAM reading → no fit claims — an unknown never fabricates a verdict).
  final int? deviceRamMb;
  const SettingsBody({
    super.key,
    required this.catalog,
    this.forceExpandDreamTeam = false,
    this.vendorCatalog,
    this.localModels = const [],
    this.edgeCatalog,
    this.deviceRamMb,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final provider = s.provider;

    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(brand: brand),
                const SizedBox(height: 20),

                // --- Run ----------------------------------------------------------------------------
                _Section(
                  title: 'Run',
                  children: [
                    _SwitchRow(
                      label: 'Demo mode',
                      help: 'Cost-free synthetic run. Turn off to use the models below with your keys.',
                      value: s.demoMode,
                      onChanged: ctrl.setDemoMode,
                    ),
                    const SizedBox(height: 14),
                    _FieldLabel('Ticker', help: 'Moves to the Hub launcher in a later release.'),
                    const SizedBox(height: 6),
                    _TickerField(value: s.ticker, onChanged: ctrl.setTicker),
                    const SizedBox(height: 16),
                    _FieldLabel(
                      'Asset type',
                      // Honest: asset_type only frames the agents' prompts (crypto vs equity). It does
                      // NOT switch data vendors — price still flows through the vendors below (yfinance
                      // serves crypto via `-USD` tickers; fundamentals won't exist). A dedicated crypto
                      // data pipeline is a future phase.
                      help: 'Frames the debate. Crypto (e.g. BTC-USD) still uses the data vendors below.',
                    ),
                    const SizedBox(height: 6),
                    _Dropdown<String>(
                      value: s.assetType,
                      items: const [
                        (label: 'Stock / equity', value: 'stock'),
                        (label: 'Crypto', value: 'crypto'),
                      ],
                      onChanged: (v) => ctrl.setAssetType(v ?? 'stock'),
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('Research depth', help: 'Debate rounds — higher is deeper but costs more.'),
                    const SizedBox(height: 6),
                    _DepthSelector(value: s.researchDepth, onChanged: ctrl.setResearchDepth),
                    const SizedBox(height: 16),
                    _FieldLabel('Output language'),
                    const SizedBox(height: 6),
                    _Dropdown<String>(
                      value: s.outputLanguage,
                      items: [for (final l in _languages) (label: l, value: l)],
                      onChanged: (v) => ctrl.setOutputLanguage(v ?? 'English'),
                    ),
                    const SizedBox(height: 16),
                    _FieldLabel('Analysts', help: 'Which analyst desks run. All on = engine default.'),
                    const SizedBox(height: 8),
                    _AnalystChips(
                      all: catalog.analysts,
                      selected: s.analysts,
                      onChanged: ctrl.setAnalysts,
                    ),
                  ],
                ),

                // --- Model ---------------------------------------------------------------------------
                _Section(
                  title: 'Model Studio',
                  children: [
                    _FieldLabel('Provider'),
                    const SizedBox(height: 6),
                    _Dropdown<String>(
                      value: provider,
                      hint: 'Select a provider',
                      items: [
                        for (final p in catalog.providerNames) (label: _providerLabel(p), value: p),
                      ],
                      onChanged: ctrl.setProvider,
                    ),
                    if (provider == null)
                      _Hint('Pick a provider to choose its models.', brand: brand)
                    else ...[
                      const SizedBox(height: 16),
                      _ModelPicker(
                        label: 'Deep model',
                        help: 'The heavy reasoning model (managers, debate).',
                        options: _foldLocalModels(provider, catalog.optionsFor(provider, 'deep'), localModels),
                        value: s.deepModel,
                        customValue: s.customDeepModel,
                        onSelected: ctrl.setDeepModel,
                        onCustom: ctrl.setCustomDeepModel,
                      ),
                      const SizedBox(height: 16),
                      _ModelPicker(
                        label: 'Quick model',
                        help: 'The fast model (analysts, tool calls).',
                        options: _foldLocalModels(provider, catalog.optionsFor(provider, 'quick'), localModels),
                        value: s.quickModel,
                        customValue: s.customQuickModel,
                        onSelected: ctrl.setQuickModel,
                        onCustom: ctrl.setCustomQuickModel,
                      ),
                      if (_effortSpec[provider] case (final label, final values)) ...[
                        const SizedBox(height: 16),
                        _FieldLabel(label),
                        const SizedBox(height: 6),
                        _Dropdown<String>(
                          value: s.effort,
                          hint: 'Default',
                          items: [for (final v in values) (label: _titleCase(v), value: v)],
                          onChanged: ctrl.setEffort,
                          allowClear: true,
                        ),
                      ],
                      if (_usesBackendUrl(provider)) ...[
                        const SizedBox(height: 16),
                        _FieldLabel(
                          'Backend URL',
                          help: _requiresBackendUrl(provider)
                              ? 'Required — your OpenAI-compatible endpoint.'
                              : 'Optional override (default $_ollamaDefaultBackendUrl).',
                        ),
                        const SizedBox(height: 6),
                        _BackendUrlField(
                          value: s.backendUrl,
                          hint: provider == 'ollama' ? _ollamaDefaultBackendUrl : 'https://…/v1',
                          required: _requiresBackendUrl(provider),
                          onChanged: ctrl.setBackendUrl,
                        ),
                      ],
                      if (providerNeedsKey(provider)) ...[
                        const SizedBox(height: 16),
                        _ApiKeyField(provider: provider),
                      ],
                    ],
                  ],
                ),

                // --- Draft Board (curated free local models, P5.1d) ----------------------------------
                // Sits between Model Studio (where the ollama provider lives) and the Dream Team
                // roster (where installed models get assigned) — supply directly above demand.
                if (edgeCatalog != null && edgeCatalog!.tiers.isNotEmpty)
                  _DraftBoardSection(
                    edgeCatalog: edgeCatalog!,
                    deviceRamMb: deviceRamMb,
                    localModels: localModels,
                  ),

                // --- Dream Team (per-role overrides) -------------------------------------------------
                _DreamTeamRoster(
                  catalog: catalog,
                  localModels: localModels,
                  initiallyExpanded: forceExpandDreamTeam || s.agentModels != null,
                ),

                // --- Data sources (per-category vendor picker, P3.1) ---------------------------------
                if (vendorCatalog != null) _DataSourcesSection(vendorCatalog: vendorCatalog!),

                // --- Benches -------------------------------------------------------------------------
                _Section(
                  title: 'Benches',
                  subtitle: 'Save the current model config (incl. the Dream Team lineup) as a preset.',
                  children: [
                    _BenchManager(benches: s.benches),
                  ],
                ),

                // --- Keys ----------------------------------------------------------------------------
                _Section(
                  title: 'Keys',
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 16, color: brand.textLo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Keys live in your OS keychain (Windows Credential Manager), never on disk '
                            'and never in logs. They are sent only to your local engine at launch.',
                            style: TextStyle(color: brand.textLo, fontSize: 11.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const _ForgetAllKeysButton(),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _titleCase(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// --- Header ----------------------------------------------------------------------------------------
class _Header extends StatelessWidget {
  final QuorumBrand brand;
  const _Header({required this.brand});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Settings',
            style: TextStyle(
                color: brand.textHi, fontSize: 22, fontWeight: FontWeight.w700, fontFamily: brand.fontUi)),
        const SizedBox(height: 4),
        Text('Choose the team that debates your ticker, and bring your own keys.',
            style: TextStyle(color: brand.textMid, fontSize: 13)),
      ],
    );
  }
}

// --- Section scaffold ------------------------------------------------------------------------------
class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: brand.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(),
              style: TextStyle(
                  color: brand.textMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TextStyle(color: brand.textLo, fontSize: 11.5)),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final String? help;
  const _FieldLabel(this.text, {this.help});
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: TextStyle(color: brand.textHi, fontSize: 13, fontWeight: FontWeight.w600)),
        if (help != null) ...[
          const SizedBox(height: 2),
          Text(help!, style: TextStyle(color: brand.textLo, fontSize: 11.5, height: 1.3)),
        ],
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final QuorumBrand brand;
  const _Hint(this.text, {required this.brand});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(text, style: TextStyle(color: brand.textLo, fontSize: 12)),
      );
}

// --- Switch row ------------------------------------------------------------------------------------
class _SwitchRow extends StatelessWidget {
  final String label;
  final String help;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow(
      {required this.label, required this.help, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _FieldLabel(label, help: help)),
        const SizedBox(width: 12),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: brand.accent,
        ),
      ],
    );
  }
}

// --- Generic dropdown ------------------------------------------------------------------------------
class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final List<({String label, T value})> items;
  final ValueChanged<T?> onChanged;
  final String? hint;

  /// When true, a leading "—" entry maps back to null (clears the selection to the engine default).
  final bool allowClear;

  /// Item values that render disabled (greyed, non-selectable) — the capability gate uses this to make
  /// a non-tool model structurally un-pickable for a tool-analyst role.
  final Set<T>? disabledValues;
  const _Dropdown(
      {required this.value,
      required this.items,
      required this.onChanged,
      this.hint,
      this.allowClear = false,
      this.disabledValues});

  bool _disabled(T v) => disabledValues != null && disabledValues!.contains(v);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Guard against a stale value not present in the current options (e.g. after a catalog change).
    final safe = items.any((i) => i.value == value) ? value : null;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: brand.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T?>(
          value: safe,
          isExpanded: true,
          isDense: true,
          dropdownColor: brand.surface2,
          iconEnabledColor: brand.textMid,
          borderRadius: BorderRadius.circular(8),
          hint: hint == null
              ? null
              : Text(hint!, style: TextStyle(color: brand.textLo, fontSize: 13)),
          style: TextStyle(color: brand.textHi, fontSize: 13, fontFamily: brand.fontUi),
          items: [
            if (allowClear)
              DropdownMenuItem<T?>(
                value: null,
                child: Text('— Default', style: TextStyle(color: brand.textLo, fontSize: 13)),
              ),
            for (final i in items)
              DropdownMenuItem<T?>(
                value: i.value,
                enabled: !_disabled(i.value),
                child: Text(i.label,
                    overflow: TextOverflow.ellipsis,
                    style: _disabled(i.value) ? TextStyle(color: brand.textLo) : null),
              ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// --- Model picker (dropdown + custom field when value == 'custom') ---------------------------------
class _ModelPicker extends StatelessWidget {
  final String label;
  final String? help;
  final List<ModelOption> options;
  final String? value;
  final String? customValue;
  final ValueChanged<String?> onSelected;
  final ValueChanged<String?> onCustom;
  const _ModelPicker({
    required this.label,
    this.help,
    required this.options,
    required this.value,
    required this.customValue,
    required this.onSelected,
    required this.onCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FieldLabel(label, help: help),
        const SizedBox(height: 6),
        _Dropdown<String>(
          value: value,
          hint: 'Default (engine picks)',
          allowClear: true,
          items: [for (final o in options) (label: o.label, value: o.value)],
          onChanged: onSelected,
        ),
        if (value == 'custom') ...[
          const SizedBox(height: 8),
          _PlainTextField(
            value: customValue,
            hint: 'Custom model id (e.g. llama3.2:latest)',
            onChanged: onCustom,
          ),
        ],
      ],
    );
  }
}

// --- Text fields -----------------------------------------------------------------------------------

/// Reconcile an uncontrolled field's controller with an externally-changed [next] value (e.g. after
/// Apply bench, or a provider switch that clears the URL). Only writes when the parent value actually
/// changed AND differs from the box, so it never fights the user's caret during ordinary typing.
/// Returns true if it wrote, so callers that derive UI from the text can [setState].
bool _reconcile(TextEditingController c, String? prev, String? next) {
  final incoming = next ?? '';
  if (next != prev && incoming != c.text) {
    c.value = TextEditingValue(
      text: incoming,
      selection: TextSelection.collapsed(offset: incoming.length),
    );
    return true;
  }
  return false;
}

class _TickerField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _TickerField({required this.value, required this.onChanged});
  @override
  State<_TickerField> createState() => _TickerFieldState();
}

class _TickerFieldState extends State<_TickerField> {
  late final TextEditingController _c = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(_TickerField old) {
    super.didUpdateWidget(old);
    _reconcile(_c, old.value, widget.value); // keep the box in sync with externally-set state
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: 160,
      child: TextField(
        controller: _c,
        onChanged: widget.onChanged,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z.\\-]')),
          _UpperCaseFormatter(),
        ],
        style: TextStyle(color: brand.textHi, fontSize: 15, fontFamily: brand.fontMono, letterSpacing: 1),
        decoration: _inputDecoration(brand, hint: 'NVDA'),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue n) =>
      n.copyWith(text: n.text.toUpperCase());
}

/// An uncontrolled text field that pushes changes up but doesn't fight the user's cursor on rebuild.
class _PlainTextField extends StatefulWidget {
  final String? value;
  final String hint;
  final ValueChanged<String?> onChanged;
  const _PlainTextField({required this.value, required this.hint, required this.onChanged});
  @override
  State<_PlainTextField> createState() => _PlainTextFieldState();
}

class _PlainTextFieldState extends State<_PlainTextField> {
  late final TextEditingController _c = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(_PlainTextField old) {
    super.didUpdateWidget(old);
    _reconcile(_c, old.value, widget.value);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return TextField(
      controller: _c,
      onChanged: (v) => widget.onChanged(v.trim().isEmpty ? null : v.trim()),
      style: TextStyle(color: brand.textHi, fontSize: 13, fontFamily: brand.fontMono),
      decoration: _inputDecoration(brand, hint: widget.hint),
    );
  }
}

class _BackendUrlField extends StatefulWidget {
  final String? value;
  final String hint;
  final bool required;
  final ValueChanged<String?> onChanged;
  const _BackendUrlField(
      {required this.value, required this.hint, required this.required, required this.onChanged});
  @override
  State<_BackendUrlField> createState() => _BackendUrlFieldState();
}

class _BackendUrlFieldState extends State<_BackendUrlField> {
  late final TextEditingController _c = TextEditingController(text: widget.value ?? '');

  @override
  void didUpdateWidget(_BackendUrlField old) {
    super.didUpdateWidget(old);
    // Reconcile after an external change (Apply bench / provider switch clearing the URL) so the box —
    // and the derived "Required" warning — reflect state rather than stale typed text.
    if (_reconcile(_c, old.value, widget.value)) setState(() {});
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final empty = _c.text.trim().isEmpty;
    return TextField(
      controller: _c,
      onChanged: (v) {
        widget.onChanged(v.trim().isEmpty ? null : v.trim());
        setState(() {}); // refresh the required-warning border
      },
      style: TextStyle(color: brand.textHi, fontSize: 13, fontFamily: brand.fontMono),
      decoration: _inputDecoration(
        brand,
        hint: widget.hint,
        error: widget.required && empty ? 'Required for this provider' : null,
      ),
    );
  }
}

InputDecoration _inputDecoration(QuorumBrand brand, {required String hint, String? error}) {
  OutlineInputBorder border(Color c) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: c),
      );
  return InputDecoration(
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    filled: true,
    fillColor: brand.surface2,
    hintText: hint,
    hintStyle: TextStyle(color: brand.textLo, fontSize: 13, fontFamily: brand.fontUi),
    errorText: error,
    errorStyle: TextStyle(color: brand.down, fontSize: 11),
    enabledBorder: border(error != null ? brand.down : brand.border),
    focusedBorder: border(error != null ? brand.down : brand.accent),
    border: border(brand.border),
  );
}

// --- Research-depth selector -----------------------------------------------------------------------
class _DepthSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _DepthSelector({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      container: true,
      label: 'Research depth, $value of 5',
      child: Row(
        children: [
          for (var i = 1; i <= 5; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _SquareToggle(
                label: '$i',
                selected: i == value,
                onTap: () => onChanged(i),
                brand: brand,
              ),
            ),
        ],
      ),
    );
  }
}

class _SquareToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final QuorumBrand brand;
  const _SquareToggle(
      {required this.label, required this.selected, required this.onTap, required this.brand});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Focusable(
        onActivate: onTap,
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? brand.accent.withValues(alpha: 0.18) : brand.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? brand.accent : brand.border),
            ),
            child: Text(label,
                style: TextStyle(
                    color: selected ? brand.textHi : brand.textMid,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
          ),
        ),
      ),
    );
  }
}

// --- Analyst chips ---------------------------------------------------------------------------------
class _AnalystChips extends StatelessWidget {
  final List<String> all;
  final List<String>? selected;
  final ValueChanged<List<String>?> onChanged;
  const _AnalystChips({required this.all, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = selected == null ? all.toSet() : selected!.toSet();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final a in all)
          _Chip(
            label: _titleCase(a),
            selected: active.contains(a),
            brand: brand,
            onTap: () {
              final next = {...active};
              if (next.contains(a)) {
                if (next.length > 1) next.remove(a); // keep at least one desk
              } else {
                next.add(a);
              }
              // All selected -> null (engine default); otherwise the explicit, catalog-ordered list.
              final list = all.where(next.contains).toList(growable: false);
              onChanged(list.length == all.length ? null : list);
            },
          ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final QuorumBrand brand;
  const _Chip(
      {required this.label, required this.selected, required this.onTap, required this.brand});
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Focusable(
        onActivate: onTap,
        borderRadius: BorderRadius.circular(20),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? brand.accent.withValues(alpha: 0.18) : brand.surface2,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? brand.accent : brand.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? Icons.check : Icons.add,
                    size: 13, color: selected ? brand.accent : brand.textLo),
                const SizedBox(width: 5),
                Text(label,
                    style: TextStyle(
                        color: selected ? brand.textHi : brand.textMid,
                        fontSize: 12.5,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- API-key field (write-only: never reads or displays a stored key) ------------------------------
class _ApiKeyField extends ConsumerStatefulWidget {
  /// The vault key this field reads/writes — a provider id (e.g. `anthropic`) or a data-vendor id
  /// (e.g. `alpha_vantage`, `fred`). Both live in the same OS keystore under their own name.
  final String provider;

  /// Display name for the paste hint. Defaults to the provider label; data vendors pass their own
  /// (e.g. 'Alpha Vantage') since they aren't in the provider-label map.
  final String? label;
  const _ApiKeyField({required this.provider, this.label});
  @override
  ConsumerState<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends ConsumerState<_ApiKeyField> {
  final _c = TextEditingController();
  bool _stored = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _refreshStored();
  }

  @override
  void didUpdateWidget(_ApiKeyField old) {
    super.didUpdateWidget(old);
    if (old.provider != widget.provider) {
      _c.clear();
      _refreshStored();
    }
  }

  Future<void> _refreshStored() async {
    final has = await ref.read(settingsControllerProvider.notifier).hasKey(widget.provider);
    if (mounted) setState(() => _stored = has);
  }

  Future<void> _save() async {
    final key = _c.text.trim();
    if (key.isEmpty) return;
    await ref.read(settingsControllerProvider.notifier).saveKey(widget.provider, key);
    _c.clear();
    if (mounted) setState(() => _stored = true);
  }

  Future<void> _clear() async {
    await ref.read(settingsControllerProvider.notifier).deleteKey(widget.provider);
    if (mounted) setState(() => _stored = false);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Re-check the vault when any key changes elsewhere (the .env seed lands, or Forget-all-keys runs)
    // so the "Stored" badge never goes stale while Settings stays open.
    ref.listen(keyVaultRevisionProvider, (_, _) => _refreshStored());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Prefix the vendor/provider name when one is passed (the data-sources vendor keys) so a
            // stored key is always attributable — the vendor dropdown can be rows away (set-01). The
            // Model Studio provider key passes no label (it sits under its Provider header) → "API key".
            _FieldLabel(widget.label != null ? '${widget.label} API key' : 'API key'),
            const SizedBox(width: 8),
            if (_stored)
              Row(children: [
                Icon(Icons.check_circle, size: 14, color: brand.up),
                const SizedBox(width: 4),
                Text('Stored', style: TextStyle(color: brand.up, fontSize: 11.5)),
              ])
            else
              Text('Not stored', style: TextStyle(color: brand.textLo, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _c,
                obscureText: _obscure,
                enableSuggestions: false,
                autocorrect: false,
                style: TextStyle(color: brand.textHi, fontSize: 13, fontFamily: brand.fontMono),
                decoration: _inputDecoration(
                  brand,
                  hint: _stored
                      ? 'Replace stored key…'
                      : 'Paste ${widget.label ?? _providerLabel(widget.provider)} key',
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                        size: 16, color: brand.textLo),
                    tooltip: _obscure ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _SmallButton(label: 'Save', onTap: _save, brand: brand, filled: true),
            if (_stored) ...[
              const SizedBox(width: 6),
              _SmallButton(label: 'Clear', onTap: _clear, brand: brand, danger: true),
            ],
          ],
        ),
      ],
    );
  }
}

// --- Data sources (per-category vendor picker) -----------------------------------------------------

/// Display names for data vendors (the catalog carries only the vendor `value`). Falls back to the raw
/// id for any vendor added engine-side but not yet mirrored here.
const _vendorLabels = <String, String>{
  'yfinance': 'Yahoo Finance',
  'alpha_vantage': 'Alpha Vantage',
  'fred': 'FRED',
  'polymarket': 'Polymarket',
};
String _vendorLabel(String v) => _vendorLabels[v] ?? v;

/// The per-category data-vendor picker (P3.1). Core (non-optional) categories get a vendor dropdown;
/// a keyed vendor selected there surfaces a required BYO-key field. The two optional categories are
/// handled honestly: macro (FRED) is a store-a-key-to-enable field that never blocks a launch, and
/// prediction markets (Polymarket, keyless) is a default-on note.
class _DataSourcesSection extends ConsumerWidget {
  final VendorCatalog vendorCatalog;
  const _DataSourcesSection({required this.vendorCatalog});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final selected = s.dataVendors ?? const <String, String>{};

    final core = vendorCatalog.categories.where((c) => !c.optional).toList(growable: false);
    final macro = vendorCatalog.categoryFor('macro_data');
    final predictionMarkets = vendorCatalog.categoryFor('prediction_markets');

    // Keyed vendors currently selected in a core category — these are REQUIRED before a real run
    // (the engine hard-raises when a core category's vendor can't authenticate). Dedup by vendor id.
    final requiredKeyed = <String>{};
    for (final c in core) {
      final chosen = selected[c.key] ?? c.defaultVendor;
      final opt = c.vendors.where((v) => v.value == chosen);
      if (opt.isNotEmpty && opt.first.needsKey) requiredKeyed.add(chosen!);
    }

    return _Section(
      title: 'Data sources',
      subtitle: 'Which vendor feeds each category. Defaults are free (Yahoo Finance); a keyed vendor '
          'needs its own BYO key stored below.',
      children: [
        for (final c in core) ...[
          _FieldLabel(c.label),
          const SizedBox(height: 6),
          _Dropdown<String>(
            value: selected[c.key] ?? c.defaultVendor,
            items: [for (final v in c.vendors) (label: _vendorLabel(v.value), value: v.value)],
            // Collapse a pick that equals the engine default back to "no override", keeping the wire
            // body minimal (only genuine overrides ride along).
            onChanged: (v) => ctrl.setDataVendor(c.key, v == c.defaultVendor ? null : v),
          ),
          const SizedBox(height: 16),
        ],
        // Required key(s) for the keyed vendors chosen above.
        for (final vendor in requiredKeyed) ...[
          _ApiKeyField(provider: vendor, label: _vendorLabel(vendor)),
          const SizedBox(height: 16),
        ],
        // Optional macro signals (FRED) — store a free key to enable; never blocks a launch.
        if (macro != null) ...[
          _FieldLabel(
            macro.label,
            help: 'Optional. Store a free FRED key to add macro-economic signals; runs work without it.',
          ),
          const SizedBox(height: 6),
          _ApiKeyField(provider: macroVendor, label: _vendorLabel(macroVendor)),
          const SizedBox(height: 16),
        ],
        // Prediction markets (Polymarket) — keyless and on by default. Lead with the honest keyless
        // statement; the engine's (verbose) category description trails as parenthetical context.
        if (predictionMarkets != null)
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 16, color: brand.textLo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Polymarket signals are on by default — no key needed. '
                  '(${predictionMarkets.label})',
                  style: TextStyle(color: brand.textLo, fontSize: 11.5, height: 1.4),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

// --- Benches ---------------------------------------------------------------------------------------
class _BenchManager extends ConsumerStatefulWidget {
  final List<Bench> benches;
  const _BenchManager({required this.benches});
  @override
  ConsumerState<_BenchManager> createState() => _BenchManagerState();
}

class _BenchManagerState extends ConsumerState<_BenchManager> {
  final _name = TextEditingController();
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final ctrl = ref.read(settingsControllerProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in widget.benches)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              color: brand.surface2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: brand.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(b.name,
                          style: TextStyle(
                              color: brand.textHi, fontSize: 13, fontWeight: FontWeight.w600)),
                      Text(_benchSummary(b),
                          style: TextStyle(color: brand.textLo, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                _SmallButton(label: 'Apply', onTap: () => ctrl.applyBench(b), brand: brand),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: brand.textLo),
                  tooltip: 'Delete',
                  onPressed: () => ctrl.deleteBench(b.name),
                ),
              ],
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                style: TextStyle(color: brand.textHi, fontSize: 13),
                decoration: _inputDecoration(brand, hint: 'New bench name'),
              ),
            ),
            const SizedBox(width: 8),
            _SmallButton(
              label: 'Save current',
              filled: true,
              brand: brand,
              onTap: () {
                final name = _name.text.trim();
                if (name.isEmpty) return;
                ctrl.saveBench(name);
                _name.clear();
              },
            ),
          ],
        ),
      ],
    );
  }

  String _benchSummary(Bench b) {
    final parts = <String>[
      if (b.provider != null) _providerLabel(b.provider!),
      if (b.effort != null) b.effort!,
      'depth ${b.researchDepth}',
    ];
    return parts.join(' · ');
  }
}

// --- Dream Team roster -----------------------------------------------------------------------------

/// The "Dream Team" section: a collapsible, stage-grouped roster of the 12 agent roles, each with a
/// per-role provider+model picker. Unassigned roles fall back to the global Model Studio quick/deep
/// pick (shown as a muted chip). Binds [settingsControllerProvider] for the live lineup.
// --- Draft Board (P5.1d) -----------------------------------------------------------------------
// The curated free-local shortlist: tiers by device RAM, per-model fit badges, installed markers,
// and the per-entry Ollama-version gate. READ-ONLY in P5.1 (the pull affordance is P5.2); the only
// interactive control is Re-detect. SCOPE WALL: this subtree renders exclusively from the typed
// EdgeModelCatalog — it must never contain a text-entry widget (enforced by draft_board_test.dart).

/// Is this entry blocked by a too-old detected Ollama? Absent (null) is NOT "older" — the banner owns
/// the absent story. A malformed detected version gates (fail-closed): garbage never silently unlocks
/// a known-incompatible model.
bool _versionGated(EdgeModelCatalog c, EdgeModel e) =>
    e.minOllamaVersion != null &&
    c.ollamaVersion != null &&
    !ollamaVersionAtLeast(c.ollamaVersion, e.minOllamaVersion!);

String _gb(int? bytes) => bytes == null ? '—' : '${(bytes / 1e9).toStringAsFixed(1)} GB';

class _DraftBoardSection extends ConsumerWidget {
  final EdgeModelCatalog edgeCatalog;
  final int? deviceRamMb;
  final List<LocalModel> localModels;
  const _DraftBoardSection(
      {required this.edgeCatalog, required this.deviceRamMb, required this.localModels});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final detected = deviceRamMb == null ? null : deviceTier(deviceRamMb!);
    final anyGated =
        edgeCatalog.tiers.any((t) => t.models.any((m) => _versionGated(edgeCatalog, m)));
    return _Section(
      title: 'Draft Board',
      subtitle: 'Curated free local models via Ollama, matched to this machine\'s memory. '
          'No API key needed. A fixed shortlist — not a model browser.',
      children: [
        _OllamaStatusBanner(version: edgeCatalog.ollamaVersion, anyGated: anyGated),
        for (final (i, tier) in edgeCatalog.tiers.indexed) ...[
          const SizedBox(height: 12),
          _TierGroup(
            tier: tier,
            label: _tierLabel(tier, i + 1 < edgeCatalog.tiers.length
                ? edgeCatalog.tiers[i + 1].minDeviceRamMb
                : null),
            isDetected: detected != null && tier.tier == detected,
            catalog: edgeCatalog,
            deviceRamMb: deviceRamMb,
            localModels: localModels,
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.info_outline, size: 14, color: brand.textLo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Fit assumes the model plus its context cache and OS headroom. Local models are '
              'slower and less capable than frontier cloud models.',
              style: TextStyle(color: brand.textLo, fontSize: 11.5, height: 1.4),
            ),
          ),
        ]),
      ],
    );
  }

  static String _tierLabel(EdgeTier t, int? nextFloorMb) {
    String gb(int mb) => '${(mb / 1000).round()} GB';
    final name = t.tierRaw.toUpperCase();
    if (t.minDeviceRamMb <= 0 && nextFloorMb != null) return '$name · UNDER ${gb(nextFloorMb)}';
    if (nextFloorMb == null) return '$name · ${gb(t.minDeviceRamMb)} +';
    return '$name · ${gb(t.minDeviceRamMb)}–${gb(nextFloorMb)}';
  }
}

class _OllamaStatusBanner extends ConsumerWidget {
  final String? version;
  final bool anyGated;
  const _OllamaStatusBanner({required this.version, required this.anyGated});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    if (version == null) {
      // Ollama absent: guidance + Re-detect (the P5.1d degraded floor; the full onboarding UX is P5.3c).
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: brand.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: brand.border),
        ),
        child: Row(children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: brand.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Ollama isn\'t installed or isn\'t running. Quorum uses it to run models locally — '
              'install it from ollama.com/download, then re-detect.',
              style: TextStyle(color: brand.textMid, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(width: 10),
          _SmallButton(
            label: 'Re-detect',
            brand: brand,
            filled: true,
            onTap: () {
              ref.invalidate(edgeModelCatalogProvider);
              ref.invalidate(localModelsProvider);
            },
          ),
        ]),
      );
    }
    final warn = anyGated;
    return Row(children: [
      Icon(warn ? Icons.warning_amber_rounded : Icons.check_circle_outline,
          size: 14, color: warn ? brand.warning : brand.textLo),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          warn
              ? 'Ollama $version detected — some models need a newer version. Update Ollama to unlock them.'
              : 'Ollama $version detected.',
          style: TextStyle(color: warn ? brand.warning : brand.textLo, fontSize: 11.5),
        ),
      ),
    ]);
  }
}

class _TierGroup extends StatelessWidget {
  final EdgeTier tier;
  final String label;
  final bool isDetected;
  final EdgeModelCatalog catalog;
  final int? deviceRamMb;
  final List<LocalModel> localModels;
  const _TierGroup(
      {required this.tier,
      required this.label,
      required this.isDetected,
      required this.catalog,
      required this.deviceRamMb,
      required this.localModels});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Text(label,
              style: TextStyle(
                  color: brand.textLo, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
          if (isDetected) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: brand.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: brand.accent),
              ),
              child: Text('THIS MACHINE',
                  style: TextStyle(
                      color: accessibleTint(brand.accent, brand.surface1),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8)),
            ),
          ],
        ]),
        const SizedBox(height: 6),
        for (final m in tier.models) ...[
          _EdgeModelRow(
            entry: m,
            gated: _versionGated(catalog, m),
            detectedVersion: catalog.ollamaVersion,
            installed: isInstalled(m, localModels),
            fit: m.fitBadgeFor(deviceRamMb, ctx: catalog.kvCtx),
            highlight: isDetected && m.isDefault,
            ollamaPresent: catalog.ollamaVersion != null,
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _EdgeModelRow extends StatelessWidget {
  final EdgeModel entry;
  final bool gated;
  final String? detectedVersion;
  final bool installed;
  final FitBadge? fit;
  final bool highlight;
  final bool ollamaPresent;
  const _EdgeModelRow(
      {required this.entry,
      required this.gated,
      required this.detectedVersion,
      required this.installed,
      required this.fit,
      required this.highlight,
      this.ollamaPresent = false});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(entry.display,
              style: TextStyle(color: brand.textHi, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(entry.ollamaTag,
              style: TextStyle(color: brand.textLo, fontSize: 11.5, fontFamily: brand.fontMono)),
          const Spacer(),
          Text(_gb(entry.bytes),
              style: TextStyle(color: brand.textMid, fontSize: 12, fontFamily: brand.fontMono)),
          if (!gated && fit != null) ...[
            const SizedBox(width: 10),
            _FitBadgeChip(fit: fit!),
          ],
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (entry.isDefault) _MiniChip('Tier default', brand.accent),
          _MiniChip(
              entry.capability == EdgeRoleCapability.analyst ? 'tools' : 'text-only',
              entry.capability == EdgeRoleCapability.analyst ? brand.up : brand.textLo),
          _MiniChip(entry.license, brand.textLo),
          if (entry.verified == 'real-run')
            _MiniChip('Verified ✓', brand.up)
          else if (entry.verified == 'tag-only')
            _MiniChip('Unverified', brand.textLo),
          if (installed) _MiniChip('Installed ✓', brand.accent),
        ]),
        const SizedBox(height: 6),
        Text(entry.blurb, style: TextStyle(color: brand.textLo, fontSize: 11.5, height: 1.3)),
      ],
    );
    return Semantics(
      label:
          '${entry.display}, ${_gb(entry.bytes)}, ${entry.license}, ${entry.capability == EdgeRoleCapability.analyst ? 'tool capable' : 'text only'}'
          '${installed ? ', installed' : ''}${gated ? ', requires a newer Ollama' : ''}',
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: brand.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: highlight ? brand.accent : brand.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (gated) Opacity(opacity: 0.45, child: content) else content,
          if (gated) ...[
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.warning_amber_rounded, size: 13, color: brand.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Requires Ollama ≥ ${entry.minOllamaVersion} — you have $detectedVersion.',
                  style: TextStyle(color: brand.warning, fontSize: 11),
                ),
              ),
            ]),
          ],
          // P5.2: the pull affordance (button / progress / error / drift). Hidden — not disabled —
          // when version-gated, Ollama absent, or the size is unknown ("every pull is an explicit
          // user click with visible size" is a locked constraint). `installed` hides only the idle
          // BUTTON inside — progress/error/drift must survive the installed flip (a drifted pull's
          // warning persists after discovery marks the row installed).
          if (!gated && ollamaPresent && entry.bytes != null)
            _PullAffordance(entry: entry, fit: fit, installed: installed),
        ]),
      ),
    );
  }
}

/// The per-row pull control (P5.2b/c), dispatched off the tag's latest snapshot. SCOPE WALL: this
/// subtree renders buttons/progress only — no text input exists in any state, and the wire request
/// is built from the TYPED catalog entry inside the controller (no string seam).
class _PullAffordance extends ConsumerStatefulWidget {
  final EdgeModel entry;
  final FitBadge? fit;
  final bool installed;
  const _PullAffordance({required this.entry, required this.fit, required this.installed});
  @override
  ConsumerState<_PullAffordance> createState() => _PullAffordanceState();
}

class _PullAffordanceState extends ConsumerState<_PullAffordance> {
  bool _confirming = false; // the two-tap Won't-fit confirm (inline, never a modal)

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final entry = widget.entry;
    final pulls = ref.watch(pullControllerProvider);
    final ctrl = ref.read(pullControllerProvider.notifier);
    final snap = pulls[entry.ollamaTag];

    // --- in flight: progress bar + honest byte counts + Cancel --------------------------------
    if (snap != null && snap.isActive) {
      final progress = snap.progress;
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              // A static zero bar + the verbatim status beats a fake indeterminate animation
              // (honest, and golden-deterministic).
              child: LinearProgressIndicator(
                value: progress ?? 0.0,
                minHeight: 5,
                backgroundColor: brand.surface1,
                valueColor: AlwaysStoppedAnimation(brand.accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            snap.phase == PullPhase.verifying
                ? 'verifying…'
                : progress == null
                    ? snap.statusRaw
                    : '${_gb(snap.completed)} / ${_gb(snap.total)}',
            style: TextStyle(color: brand.textMid, fontSize: 11, fontFamily: brand.fontMono),
          ),
          const SizedBox(width: 10),
          _SmallButton(label: 'Cancel', brand: brand, onTap: () => ctrl.cancel(entry.ollamaTag)),
        ]),
      );
    }

    // --- terminal error: the server's message verbatim + Retry --------------------------------
    if (snap != null && snap.phase == PullPhase.error) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(Icons.error_outline, size: 13, color: brand.down),
          const SizedBox(width: 6),
          Expanded(
            child: Text(snap.error ?? 'the pull failed',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: brand.down, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          _SmallButton(label: 'Retry', brand: brand, onTap: () => ctrl.start(entry)),
        ]),
      );
    }

    // --- drift after success: the tag changed upstream — surface it, don't hide it ------------
    if (snap != null && snap.phase == PullPhase.success && snap.drift) {
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: brand.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Downloaded size differs from the curated catalog — the tag may have changed upstream.',
              style: TextStyle(color: brand.warning, fontSize: 11),
            ),
          ),
        ]),
      );
    }

    // --- idle / cancelled: the Pull (or Resume) button. Installed rows get no button (nothing
    // to do — no re-pull affordance in V1), but the branches above still render for them. --------
    if (widget.installed) return const SizedBox.shrink();
    final cancelled = snap != null && snap.phase == PullPhase.cancelled;
    final label = '${cancelled ? 'Resume' : 'Pull'} · ${_gb(entry.bytes)}';
    final blocked = ctrl.anyActive; // V1 policy: one download at a time

    if (_confirming) {
      // The Won't-fit two-tap: the badge is advisory (the user may know better), but intent is
      // confirmed inline before a multi-GB download that the fit math says exceeds this machine.
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, size: 13, color: brand.warning),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'May not run on this machine — the fit estimate says it exceeds available memory.',
              style: TextStyle(color: brand.warning, fontSize: 11),
            ),
          ),
          const SizedBox(width: 8),
          _SmallButton(
              label: 'Pull anyway · ${_gb(entry.bytes)}',
              brand: brand,
              filled: true,
              // Same one-download gate as the idle button: a strip opened BEFORE another pull
              // started must not become a second concurrent multi-GB download (#52 review).
              enabled: !blocked,
              onTap: () {
                setState(() => _confirming = false);
                ctrl.start(entry);
              }),
          const SizedBox(width: 6),
          _SmallButton(
              label: 'Keep browsing',
              brand: brand,
              onTap: () => setState(() => _confirming = false)),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      // Row(min), not Align: _SmallButton's Container has an alignment, which expands to the max
      // width under Align's bounded-loose constraints — a min Row gives it unbounded width, so the
      // button shrink-wraps to its label (the compact chip the design calls for).
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _SmallButton(
          label: label,
          brand: brand,
          filled: true,
          enabled: !blocked,
          onTap: () {
            if (widget.fit == FitBadge.wontFit) {
              setState(() => _confirming = true); // first tap never starts a Won't-fit pull
            } else {
              ctrl.start(entry);
            }
          },
        ),
      ]),
    );
  }
}

class _FitBadgeChip extends StatelessWidget {
  final FitBadge fit;
  const _FitBadgeChip({required this.fit});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (label, hue) = switch (fit) {
      FitBadge.fits => ('Fits', brand.up),
      FitBadge.tight => ('Tight', brand.warning),
      FitBadge.wontFit => ("Won't fit", brand.down),
    };
    final ink = accessibleTint(hue, brand.surface2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hue.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(label,
          style: TextStyle(color: ink, fontSize: 10.5, fontWeight: FontWeight.w700)),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final Color hue;
  const _MiniChip(this.label, this.hue);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: hue.withValues(alpha: 0.55)),
      ),
      child: Text(label,
          style: TextStyle(
              color: accessibleTint(hue, brand.surface2), fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _DreamTeamRoster extends ConsumerStatefulWidget {
  final Catalog catalog;
  final List<LocalModel> localModels;
  final bool initiallyExpanded;
  const _DreamTeamRoster(
      {required this.catalog, this.localModels = const [], this.initiallyExpanded = false});
  @override
  ConsumerState<_DreamTeamRoster> createState() => _DreamTeamRosterState();
}

class _DreamTeamRosterState extends ConsumerState<_DreamTeamRoster> {
  late bool _expanded = widget.initiallyExpanded;

  /// Transient apply-to-all / per-stage source. Null until a complete model is chosen in the
  /// "Set all roles to…" picker — never persisted.
  AgentModel? _applyTarget;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final s = ref.watch(settingsControllerProvider);
    final ctrl = ref.read(settingsControllerProvider.notifier);
    final models = s.agentModels;
    final assigned = dreamTeamRoleKeys.where((k) => _roleAssigned(models?[k])).length;

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: brand.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: 'Dream Team, $assigned of 12 roles assigned',
            child: Focusable(
              onActivate: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('DREAM TEAM',
                            style: TextStyle(
                                color: brand.textMid,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 4),
                        Text('Pin a model to any role. Unassigned roles fall back to your Model Studio pick.',
                            style: TextStyle(color: brand.textLo, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _CountBadge(assigned: assigned, total: dreamTeamRoleKeys.length, brand: brand),
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20, color: brand.textMid),
                ],
              ),
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 12),
            // Apply-to-all / per-stage source picker.
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                color: brand.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: brand.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FieldLabel('Set all roles to…',
                      help: 'Pick one model, then apply it to the whole team or a single stage.'),
                  const SizedBox(height: 8),
                  _ModelAssignmentPicker(
                    catalog: widget.catalog,
                    localModels: widget.localModels,
                    initial: null,
                    onChanged: (m) => setState(() => _applyTarget = m),
                    // Apply-to-all can land on the tool roles, so use the strict block gate.
                    gate: RoleGate.block,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _SmallButton(
                        label: 'Apply to all',
                        filled: true,
                        enabled: _applyTarget != null,
                        brand: brand,
                        onTap: () => ctrl.setAllAgentModels(_applyTarget!),
                      ),
                      const SizedBox(width: 8),
                      _SmallButton(
                        label: 'Clear all',
                        danger: true,
                        enabled: assigned > 0,
                        brand: brand,
                        onTap: ctrl.clearAgentModels,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            for (final (stageLabel, keys) in dreamTeamStages)
              _RosterStage(
                stageLabel: stageLabel,
                roleKeys: keys,
                catalog: widget.catalog,
                localModels: widget.localModels,
                models: models,
                applyTarget: _applyTarget,
                onAssign: ctrl.setAgentModel,
                onSetStage: (roleKeys, model) {
                  for (final role in roleKeys) {
                    ctrl.setAgentModel(role, model);
                  }
                },
              ),
          ],
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  final int assigned;
  final int total;
  final QuorumBrand brand;
  const _CountBadge({required this.assigned, required this.total, required this.brand});
  @override
  Widget build(BuildContext context) {
    final on = assigned > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on ? brand.accent.withValues(alpha: 0.16) : brand.surface2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: on ? brand.accent : brand.border),
      ),
      child: Text('$assigned of $total',
          style: TextStyle(
              color: on ? brand.textHi : brand.textLo,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// One stage group: an uppercased header (with a "Set stage" affordance) + its role rows.
class _RosterStage extends StatelessWidget {
  final String stageLabel;
  final List<String> roleKeys;
  final Catalog catalog;
  final List<LocalModel> localModels;
  final Map<String, AgentModel>? models;
  final AgentModel? applyTarget;
  final void Function(String role, AgentModel? model) onAssign;
  final void Function(List<String> roleKeys, AgentModel model) onSetStage;
  const _RosterStage({
    required this.stageLabel,
    required this.roleKeys,
    required this.catalog,
    required this.localModels,
    required this.models,
    required this.applyTarget,
    required this.onAssign,
    required this.onSetStage,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(stageLabel.toUpperCase(),
                    style: TextStyle(
                        color: brand.textLo,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
              ),
              _SetStageButton(
                enabled: applyTarget != null,
                brand: brand,
                onTap: () => onSetStage(roleKeys, applyTarget!),
              ),
            ],
          ),
        ),
        for (final role in roleKeys)
          _RoleRow(
            roleKey: role,
            catalog: catalog,
            localModels: localModels,
            current: models?[role],
            onAssign: (m) => onAssign(role, m),
          ),
      ],
    );
  }
}

/// A compact "Set stage" text affordance on a stage header (greyed until an apply target is picked).
class _SetStageButton extends StatelessWidget {
  final bool enabled;
  final QuorumBrand brand;
  final VoidCallback onTap;
  const _SetStageButton({required this.enabled, required this.brand, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: 'Set stage',
        child: Focusable(
          onActivate: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(4),
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Text('Set stage',
                style: TextStyle(color: brand.accent, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// A single role: a tappable summary line (label + assigned/fallback chip) that discloses the
/// per-role provider+model picker. The picker's transient half-set state lives in
/// [_ModelAssignmentPicker]; this row only forwards complete assignments (or null) to [onAssign].
class _RoleRow extends StatefulWidget {
  final String roleKey;
  final Catalog catalog;
  final List<LocalModel> localModels;
  final AgentModel? current;
  final ValueChanged<AgentModel?> onAssign;
  const _RoleRow(
      {required this.roleKey,
      required this.catalog,
      required this.localModels,
      required this.current,
      required this.onAssign});
  @override
  State<_RoleRow> createState() => _RoleRowState();
}

class _RoleRowState extends State<_RoleRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: brand.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: '${dreamTeamRoleLabel(widget.roleKey)} model',
            child: Focusable(
              onActivate: () => setState(() => _open = !_open),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
                  child: Row(
                  children: [
                    Expanded(
                      child: Text(dreamTeamRoleLabel(widget.roleKey),
                          style: TextStyle(
                              color: brand.textHi, fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                        child: _RoleChip(
                            roleKey: widget.roleKey,
                            model: widget.current,
                            catalog: widget.catalog,
                            localModels: widget.localModels)),
                    const SizedBox(width: 6),
                    Icon(_open ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: brand.textLo),
                  ],
                ),
              ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ModelAssignmentPicker(
                catalog: widget.catalog,
                localModels: widget.localModels,
                initial: widget.current,
                onChanged: widget.onAssign,
                gate: roleGateClass(widget.roleKey),
              ),
            ),
        ],
      ),
    );
  }
}

/// The assigned/fallback chip on a role's summary line. Assigned → solid accent showing
/// "provider · model"; unassigned → muted "Falls back · QUICK/DEEP" (DEEP for the two judges). When an
/// assignment is capability-invalid (a stale Bench/applied combo the picker would now block), the chip
/// recolors: red for a tool role holding a non-tool model, amber for an unverified/degraded combo —
/// the only place a never-opened bad assignment can surface.
class _RoleChip extends StatelessWidget {
  final String roleKey;
  final AgentModel? model;
  final Catalog catalog;
  final List<LocalModel> localModels;
  const _RoleChip(
      {required this.roleKey,
      required this.model,
      required this.catalog,
      this.localModels = const []});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final assigned = _roleAssigned(model);
    final outcome = assigned
        ? _gateOutcome(
            roleGateClass(roleKey), _toolCapableOf(catalog, model!.provider, model!.model, localModels))
        : _GateOutcome.ok;
    final label = assigned
        ? '${_providerLabel(model!.provider)} · ${model!.model}'
        : 'Falls back · ${roleFallsBackToDeep(roleKey) ? 'DEEP' : 'QUICK'}';
    final (Color border, Color fill, Color fg, IconData? icon) = switch (outcome) {
      _GateOutcome.block => (brand.down, brand.down.withValues(alpha: 0.14), brand.down, Icons.error_outline),
      _GateOutcome.warn => (brand.warning, brand.warning.withValues(alpha: 0.14), brand.warning, Icons.warning_amber),
      _GateOutcome.ok when assigned => (brand.accent, brand.accent.withValues(alpha: 0.18), brand.textHi, null),
      _GateOutcome.ok => (brand.border, brand.surface1, brand.textLo, null),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      // OK chips render the bare Text exactly as before (byte-identical goldens); only warn/block add
      // a leading icon (and thus the Row).
      child: icon == null
          ? Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: fg, fontSize: 11, fontWeight: assigned ? FontWeight.w600 : FontWeight.w500))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
    );
  }
}

/// A provider+model picker that emits a COMPLETE [AgentModel] (or null to unassign) — never a
/// half-set/blank-model object. The in-progress provider (chosen before a model) lives only in this
/// widget's State; [onChanged] fires null until a real model (a concrete option, or a non-empty
/// custom id) is selected. This single invariant prevents an `AgentModel(model: '')` ever reaching
/// the wire (where the engine and the manifest both silently drop it, making the roster lie).
class _ModelAssignmentPicker extends StatefulWidget {
  final Catalog catalog;
  final List<LocalModel> localModels;
  final AgentModel? initial;
  final ValueChanged<AgentModel?> onChanged;

  /// The capability gate for the target role: block (tool roles — non-tool models are disabled),
  /// warn (structured roles), or none. The apply-to-all picker uses the strict [RoleGate.block].
  final RoleGate gate;
  const _ModelAssignmentPicker(
      {required this.catalog,
      this.localModels = const [],
      required this.initial,
      required this.onChanged,
      required this.gate});
  @override
  State<_ModelAssignmentPicker> createState() => _ModelAssignmentPickerState();
}

class _ModelAssignmentPickerState extends State<_ModelAssignmentPicker> {
  String? _provider;
  String? _modelSelection; // a catalog option value, or the 'custom' sentinel, or null
  String _customText = '';
  bool _customMode = false;

  @override
  void initState() {
    super.initState();
    _seedFromInitial();
  }

  void _seedFromInitial() {
    final m = widget.initial;
    _provider = m?.provider;
    final model = m?.model;
    if (_provider != null && model != null && model.isNotEmpty) {
      final known = _unionModels(widget.catalog, _provider!, widget.localModels)
          .any((o) => o.value == model && o.value != 'custom');
      if (known) {
        _modelSelection = model;
      } else {
        _modelSelection = 'custom';
        _customMode = true;
        _customText = model;
      }
    }
  }

  /// The effective model id from the current selection: null when nothing real is chosen.
  String? _effectiveModel() {
    if (_modelSelection == 'custom') {
      final t = _customText.trim();
      return t.isEmpty ? null : t;
    }
    return _modelSelection;
  }

  void _emit() {
    final p = _provider;
    final m = _effectiveModel();
    widget.onChanged(
        (p != null && m != null && m.isNotEmpty) ? AgentModel(provider: p, model: m) : null);
  }

  void _onProvider(String? p) => setState(() {
        _provider = p;
        _modelSelection = null; // a model from the old provider is invalid; clear it
        _customMode = false;
        _customText = '';
        _emit(); // unassigned until a model is picked for the new provider
      });

  void _onModel(String? v) => setState(() {
        _modelSelection = v;
        _customMode = v == 'custom';
        _emit();
      });

  void _onCustom(String? v) => setState(() {
        _customText = v ?? '';
        _emit();
      });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final provider = _provider;
    // Block gate: a known-non-tool model is disabled (un-pickable) on a tool role; its label gets a
    // "· no tools" tag. Unknown (null) stays enabled — it warns, never blocks.
    final models =
        provider == null ? const <ModelOption>[] : _unionModels(widget.catalog, provider, widget.localModels);
    final blocked = <String>{
      if (widget.gate == RoleGate.block)
        for (final o in models)
          if (o.toolCapable == false) o.value,
    };
    final outcome = _gateOutcome(
        widget.gate, _toolCapableOf(widget.catalog, provider, _effectiveModel(), widget.localModels));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Dropdown<String>(
          value: provider,
          hint: 'Provider',
          allowClear: true, // '— Default' clears the role back to the quick/deep fallback
          items: [for (final p in _rosterProviders(widget.catalog)) (label: _providerLabel(p), value: p)],
          onChanged: _onProvider,
        ),
        if (provider != null) ...[
          const SizedBox(height: 8),
          _Dropdown<String>(
            value: _modelSelection,
            hint: 'Model',
            disabledValues: blocked.isEmpty ? null : blocked,
            items: [
              for (final o in models)
                (label: blocked.contains(o.value) ? '${o.label}  ·  no tools' : o.label, value: o.value),
            ],
            onChanged: _onModel,
          ),
          if (_customMode) ...[
            const SizedBox(height: 8),
            _PlainTextField(
              value: _customText,
              hint: 'Custom model id (e.g. llama3.2:latest)',
              onChanged: _onCustom,
            ),
          ],
          if (outcome != _GateOutcome.ok) ...[
            const SizedBox(height: 8),
            _CapabilityNotice(outcome: outcome, gate: widget.gate, brand: brand),
          ],
        ],
      ],
    );
  }
}

/// An inline capability advisory under a per-role picker: red when the selected model can't tool-call
/// on a tool role (block), amber when tool support is unverified (custom/unknown) or a structured role
/// may degrade to free-text. Never gates by itself — the disabled dropdown item is the hard block.
class _CapabilityNotice extends StatelessWidget {
  final _GateOutcome outcome;
  final RoleGate gate;
  final QuorumBrand brand;
  const _CapabilityNotice({required this.outcome, required this.gate, required this.brand});

  @override
  Widget build(BuildContext context) {
    final isBlock = outcome == _GateOutcome.block;
    final color = isBlock ? brand.down : brand.warning;
    final text = isBlock
        ? 'This model can’t do tool calls — it would return an empty report. Pick a tool-capable model.'
        : gate == RoleGate.block
            ? 'Tool support unverified — this role may return an empty report.'
            : 'May degrade to free-text; rating extraction is best-effort.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(isBlock ? Icons.error_outline : Icons.warning_amber, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: color, fontSize: 11, height: 1.3)),
        ),
      ],
    );
  }
}

// --- Forget all keys -------------------------------------------------------------------------------
class _ForgetAllKeysButton extends ConsumerWidget {
  const _ForgetAllKeysButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        icon: Icon(Icons.delete_sweep_outlined, size: 16, color: brand.down),
        label: Text('Forget all keys', style: TextStyle(color: brand.down, fontSize: 12.5)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: brand.down.withValues(alpha: 0.5)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: brand.surface1,
              title: Text('Forget all keys?', style: TextStyle(color: brand.textHi)),
              content: Text(
                'This deletes every Quorum API key from your OS keychain. Other apps’ credentials '
                'are untouched. This cannot be undone.',
                style: TextStyle(color: brand.textMid, fontSize: 13),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text('Cancel', style: TextStyle(color: brand.textMid))),
                TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Forget', style: TextStyle(color: brand.down))),
              ],
            ),
          );
          if (ok == true) {
            await ref.read(settingsControllerProvider.notifier).forgetAllKeys();
          }
        },
      ),
    );
  }
}

// --- Small button ----------------------------------------------------------------------------------
class _SmallButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final QuorumBrand brand;
  final bool filled;
  final bool danger;
  final bool enabled;
  const _SmallButton(
      {required this.label,
      required this.onTap,
      required this.brand,
      this.filled = false,
      this.danger = false,
      this.enabled = true});
  @override
  Widget build(BuildContext context) {
    // P3.4b: a filled button's label uses onAccent (AA-normal 4.97:1) — white was 3.77:1 on the accent fill.
    final fg = danger ? brand.down : (filled ? brand.onAccent : brand.textHi);
    final bg = filled ? brand.accent : Colors.transparent;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Focusable(
          onActivate: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(8),
          child: GestureDetector(
            onTap: enabled ? onTap : null,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: filled ? brand.accent : brand.border),
              ),
              child: Text(label,
                  style: TextStyle(color: fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
      ),
    );
  }
}

// --- Loading / error / empty notices ---------------------------------------------------------------
class _CenterNotice extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool spinner;
  final VoidCallback? onRetry;
  const _CenterNotice({required this.title, this.subtitle, this.spinner = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (spinner)
            SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: brand.accent))
          else
            Icon(Icons.cloud_off_outlined, size: 30, color: brand.textLo),
          const SizedBox(height: 14),
          Text(title,
              style: TextStyle(color: brand.textHi, fontSize: 15, fontWeight: FontWeight.w600)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: brand.textLo, fontSize: 12.5)),
            ),
          ],
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            _SmallButton(label: 'Retry', onTap: onRetry!, brand: brand, filled: true),
          ],
        ],
      ),
    );
  }
}

/// Reads the brand tokens from the theme — the intended access path for new surfaces. Falls back to
/// the const dark brand if (somehow) unregistered, so this never throws in a stray test harness.
extension _BrandX on BuildContext {
  QuorumBrand get brand =>
      Theme.of(this).extension<QuorumBrand>() ?? const QuorumBrand.dark();
}
