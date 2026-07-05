import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../dream_team_roster.dart';
import '../provider_meta.dart'; // providerNeedsKey (+ the shared provider->key-env mirror)
import '../vendor_meta.dart' show macroVendor; // data-vendor key metadata (mirrors VENDOR_API_KEY_ENV)
import '../state/catalog_provider.dart'; // catalogProvider, engineConnectionProvider
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

/// A role's full model set = the dedup-by-value union of the provider's quick + deep options, plus
/// exactly one trailing `custom` sentinel (deduped, so a catalog that already lists `custom` doesn't
/// double it). Prevents DropdownButton duplicate-value asserts when a model appears in both tiers.
List<ModelOption> _unionModels(Catalog c, String provider) {
  final seen = <String>{};
  final out = <ModelOption>[];
  for (final o in [...c.optionsFor(provider, 'quick'), ...c.optionsFor(provider, 'deep')]) {
    if (seen.add(o.value)) out.add(o);
  }
  if (seen.add('custom')) out.add(const ModelOption('Custom model id…', 'custom'));
  return out;
}

/// A role is *assigned* iff it carries a provider AND a non-blank model. The single predicate the wire
/// commit, the chip, and the count all share — so the UI can never read "assigned" while the engine
/// (which drops a blank-model spec) runs the fallback.
bool _roleAssigned(AgentModel? m) => m != null && m.model.trim().isNotEmpty;

/// The catalog's `tool_capable` flag for a (provider, model), or null when the model isn't a catalog
/// option — a custom/retired id we can't classify. null = UNKNOWN, which WARNS (never blocks).
bool? _toolCapableOf(Catalog catalog, String? provider, String? model) {
  if (provider == null || model == null || model.trim().isEmpty) return null;
  for (final o in _unionModels(catalog, provider)) {
    if (o.value == model) return o.toolCapable;
  }
  return null;
}

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
    return Container(
      color: brand.bg,
      child: catalog.when(
        data: (c) => c.providers.isEmpty
            ? _CenterNotice(
                title: 'No providers available',
                subtitle: 'The engine returned an empty catalog.',
                onRetry: _retry)
            : SettingsBody(catalog: c, vendorCatalog: vendorCatalog),
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
  const SettingsBody({
    super.key,
    required this.catalog,
    this.forceExpandDreamTeam = false,
    this.vendorCatalog,
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
                        options: catalog.optionsFor(provider, 'deep'),
                        value: s.deepModel,
                        customValue: s.customDeepModel,
                        onSelected: ctrl.setDeepModel,
                        onCustom: ctrl.setCustomDeepModel,
                      ),
                      const SizedBox(height: 16),
                      _ModelPicker(
                        label: 'Quick model',
                        help: 'The fast model (analysts, tool calls).',
                        options: catalog.optionsFor(provider, 'quick'),
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

                // --- Dream Team (per-role overrides) -------------------------------------------------
                _DreamTeamRoster(
                  catalog: catalog,
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
            _FieldLabel('API key'),
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
        // Prediction markets (Polymarket) — keyless and on by default.
        if (predictionMarkets != null)
          Row(
            children: [
              Icon(Icons.insights_outlined, size: 16, color: brand.textLo),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${predictionMarkets.label}: Polymarket signals are on by default — no key needed.',
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
class _DreamTeamRoster extends ConsumerStatefulWidget {
  final Catalog catalog;
  final bool initiallyExpanded;
  const _DreamTeamRoster({required this.catalog, this.initiallyExpanded = false});
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
  final Map<String, AgentModel>? models;
  final AgentModel? applyTarget;
  final void Function(String role, AgentModel? model) onAssign;
  final void Function(List<String> roleKeys, AgentModel model) onSetStage;
  const _RosterStage({
    required this.stageLabel,
    required this.roleKeys,
    required this.catalog,
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
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: Text('Set stage',
              style: TextStyle(color: brand.accent, fontSize: 10.5, fontWeight: FontWeight.w700)),
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
  final AgentModel? current;
  final ValueChanged<AgentModel?> onAssign;
  const _RoleRow(
      {required this.roleKey,
      required this.catalog,
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
                            catalog: widget.catalog)),
                    const SizedBox(width: 6),
                    Icon(_open ? Icons.expand_less : Icons.expand_more,
                        size: 18, color: brand.textLo),
                  ],
                ),
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ModelAssignmentPicker(
                catalog: widget.catalog,
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
  const _RoleChip({required this.roleKey, required this.model, required this.catalog});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final assigned = _roleAssigned(model);
    final outcome = assigned
        ? _gateOutcome(roleGateClass(roleKey), _toolCapableOf(catalog, model!.provider, model!.model))
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
  final AgentModel? initial;
  final ValueChanged<AgentModel?> onChanged;

  /// The capability gate for the target role: block (tool roles — non-tool models are disabled),
  /// warn (structured roles), or none. The apply-to-all picker uses the strict [RoleGate.block].
  final RoleGate gate;
  const _ModelAssignmentPicker(
      {required this.catalog, required this.initial, required this.onChanged, required this.gate});
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
      final known = _unionModels(widget.catalog, _provider!)
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
    final models = provider == null ? const <ModelOption>[] : _unionModels(widget.catalog, provider);
    final blocked = <String>{
      if (widget.gate == RoleGate.block)
        for (final o in models)
          if (o.toolCapable == false) o.value,
    };
    final outcome = _gateOutcome(widget.gate, _toolCapableOf(widget.catalog, provider, _effectiveModel()));
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
    final fg = danger ? brand.down : (filled ? Colors.white : brand.textHi);
    final bg = filled ? brand.accent : Colors.transparent;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
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
