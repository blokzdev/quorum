import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

import '../state/catalog_provider.dart'; // catalogProvider, engineConnectionProvider
import '../state/run_controller.dart' show httpClientProvider;
import '../state/settings_controller.dart';
import 'brand.dart';

// --- Engine contract mirrors -----------------------------------------------------------------------
// The desktop can't import the Python maps and the catalog endpoint doesn't carry them, so these are
// hand-kept in sync with the engine. Each has a pointer to its source of truth.

/// Provider -> API-key env var, mirroring `tradingagents/llm_clients/api_key_env.py`
/// PROVIDER_API_KEY_ENV. A non-null value means the provider authenticates with a key, so Model
/// Studio shows the (write-only) key field. `null` (bedrock = AWS chain, ollama = local) hides it.
const _providerKeyEnv = <String, String?>{
  'openai': 'OPENAI_API_KEY',
  'anthropic': 'ANTHROPIC_API_KEY',
  'google': 'GOOGLE_API_KEY',
  'azure': 'AZURE_OPENAI_API_KEY',
  'bedrock': null,
  'xai': 'XAI_API_KEY',
  'deepseek': 'DEEPSEEK_API_KEY',
  'qwen': 'DASHSCOPE_API_KEY',
  'qwen-cn': 'DASHSCOPE_CN_API_KEY',
  'glm': 'ZHIPU_API_KEY',
  'glm-cn': 'ZHIPU_CN_API_KEY',
  'minimax': 'MINIMAX_API_KEY',
  'minimax-cn': 'MINIMAX_CN_API_KEY',
  'openrouter': 'OPENROUTER_API_KEY',
  'mistral': 'MISTRAL_API_KEY',
  'kimi': 'MOONSHOT_API_KEY',
  'groq': 'GROQ_API_KEY',
  'nvidia': 'NVIDIA_API_KEY',
  'ollama': null,
  'openai_compatible': 'OPENAI_COMPATIBLE_API_KEY',
};

bool _needsKey(String provider) => _providerKeyEnv[provider] != null;

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
    return Container(
      color: brand.bg,
      child: catalog.when(
        data: (c) => c.providers.isEmpty
            ? _CenterNotice(
                title: 'No providers available',
                subtitle: 'The engine returned an empty catalog.',
                onRetry: _retry)
            : SettingsBody(catalog: c),
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
  const SettingsBody({super.key, required this.catalog});

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
                      if (_needsKey(provider)) ...[
                        const SizedBox(height: 16),
                        _ApiKeyField(provider: provider),
                      ],
                    ],
                  ],
                ),

                // --- Benches -------------------------------------------------------------------------
                _Section(
                  title: 'Benches',
                  subtitle: 'Save the current model config as a reusable preset.',
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
  const _Dropdown(
      {required this.value,
      required this.items,
      required this.onChanged,
      this.hint,
      this.allowClear = false});

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
                child: Text(i.label, overflow: TextOverflow.ellipsis),
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
  final String provider;
  const _ApiKeyField({required this.provider});
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
                  hint: _stored ? 'Replace stored key…' : 'Paste ${_providerLabel(widget.provider)} key',
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
  const _SmallButton(
      {required this.label,
      required this.onTap,
      required this.brand,
      this.filled = false,
      this.danger = false});
  @override
  Widget build(BuildContext context) {
    final fg = danger ? brand.down : (filled ? Colors.white : brand.textHi);
    final bg = filled ? brand.accent : Colors.transparent;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
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
