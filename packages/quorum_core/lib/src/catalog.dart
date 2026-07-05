/// Typed view of `GET /catalog/providers` — the provider/model catalog the engine serves from
/// `model_catalog.py`. Tolerant of missing keys so a catalog bump never hard-fails the client.
library;

class ModelOption {
  final String label;
  final String value;

  /// Whether this model can do tool-calling, surfaced per option on `/catalog` (`tool_capable`):
  /// `true`/`false` when known, `null` when unknown (a `custom`/local id the engine can't classify).
  /// Feeds the Dream Team capability gate — the tool-analyst roles BLOCK a `false`, WARN on `null`.
  /// Additive + tolerant: a payload without the key reads as `null`.
  final bool? toolCapable;
  const ModelOption(this.label, this.value, {this.toolCapable});

  factory ModelOption.fromJson(Map<String, dynamic> j) => ModelOption(
        j['label'] as String? ?? '',
        j['value'] as String? ?? '',
        toolCapable: j['tool_capable'] as bool?,
      );
}

class ProviderCatalog {
  final String name;

  /// selection mode (`quick` | `deep`) -> options.
  final Map<String, List<ModelOption>> modes;
  const ProviderCatalog(this.name, this.modes);

  List<ModelOption> optionsFor(String mode) => modes[mode] ?? const [];
}

class Catalog {
  final int contractVersion;
  final Map<String, ProviderCatalog> providers;
  final List<String> analysts;

  const Catalog({this.contractVersion = 0, this.providers = const {}, this.analysts = const []});

  factory Catalog.fromJson(Map<String, dynamic> j) {
    final providers = <String, ProviderCatalog>{};
    ((j['providers'] as Map?) ?? const {}).forEach((prov, modesRaw) {
      final modes = <String, List<ModelOption>>{};
      ((modesRaw as Map?) ?? const {}).forEach((mode, optsRaw) {
        modes[mode as String] = ((optsRaw as List?) ?? const [])
            .map((o) => ModelOption.fromJson((o as Map).cast<String, dynamic>()))
            .toList(growable: false);
      });
      final name = prov as String;
      providers[name] = ProviderCatalog(name, modes);
    });
    return Catalog(
      contractVersion: (j['contract_version'] as num?)?.toInt() ?? 0,
      providers: providers,
      analysts:
          ((j['analysts'] as List?) ?? const []).map((e) => e as String).toList(growable: false),
    );
  }

  List<String> get providerNames => providers.keys.toList(growable: false);

  List<ModelOption> optionsFor(String provider, String mode) =>
      providers[provider]?.optionsFor(mode) ?? const [];
}

// --- Data-vendor catalog (P3.1) --------------------------------------------------------------------

/// One selectable data vendor for a category, from `GET /catalog/vendors`. [needsKey]/[keyEnv] are
/// single-sourced from the engine's vendor->env map, so the UI can't disagree with what gets injected.
class VendorOption {
  final String value;
  final bool needsKey;
  final String? keyEnv;
  const VendorOption(this.value, {this.needsKey = false, this.keyEnv});

  factory VendorOption.fromJson(Map<String, dynamic> j) => VendorOption(
        j['value'] as String? ?? '',
        needsKey: j['needs_key'] as bool? ?? false,
        keyEnv: j['key_env'] as String?,
      );
}

/// One data category (e.g. `core_stock_apis`) with its selectable vendors. [optional] categories
/// (macro/prediction) degrade gracefully when their vendor is unavailable; [defaultVendor] is what
/// the engine uses when the user picks nothing.
class VendorCategory {
  final String key;
  final String label;
  final bool optional;
  final String? defaultVendor;
  final List<VendorOption> vendors;
  const VendorCategory(this.key, this.label,
      {this.optional = false, this.defaultVendor, this.vendors = const []});

  factory VendorCategory.fromJson(Map<String, dynamic> j) => VendorCategory(
        j['key'] as String? ?? '',
        j['label'] as String? ?? '',
        optional: j['optional'] as bool? ?? false,
        defaultVendor: j['default'] as String?,
        vendors: ((j['vendors'] as List?) ?? const [])
            .map((v) => VendorOption.fromJson((v as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

/// Typed view of `GET /catalog/vendors` — the per-category data-vendor picker for Model Studio.
/// Tolerant of missing keys so a catalog bump never hard-fails the client.
class VendorCatalog {
  final int contractVersion;
  final List<VendorCategory> categories;
  const VendorCatalog({this.contractVersion = 0, this.categories = const []});

  factory VendorCatalog.fromJson(Map<String, dynamic> j) => VendorCatalog(
        contractVersion: (j['contract_version'] as num?)?.toInt() ?? 0,
        categories: ((j['categories'] as List?) ?? const [])
            .map((c) => VendorCategory.fromJson((c as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );

  VendorCategory? categoryFor(String key) {
    for (final c in categories) {
      if (c.key == key) return c;
    }
    return null;
  }
}

// --- Local-model discovery (P3.2) ------------------------------------------------------------------

/// One installed local (Ollama) model from `GET /catalog/local-models`. [toolCapable] mirrors the
/// engine's per-model capability probe: `true`/`false` when Ollama reports it, `null` when unknown (an
/// older Ollama that omits `capabilities`) — the picker's gate WARNS on `null`, never blocks.
class LocalModel {
  final String name;
  final bool? toolCapable;
  final int? size;
  final String? family;
  const LocalModel(this.name, {this.toolCapable, this.size, this.family});

  factory LocalModel.fromJson(Map<String, dynamic> j) => LocalModel(
        j['name'] as String? ?? '',
        toolCapable: j['tool_capable'] as bool?,
        size: (j['size'] as num?)?.toInt(),
        family: j['family'] as String?,
      );

  /// As a picker option: the raw model id is both label and value, carrying [toolCapable] so the
  /// capability gate treats a discovered non-tool model exactly like a catalog one.
  ModelOption toOption() => ModelOption(name, name, toolCapable: toolCapable);

  static List<LocalModel> listFromJson(Map<String, dynamic> j) =>
      ((j['local_models'] as List?) ?? const [])
          .map((m) => LocalModel.fromJson((m as Map).cast<String, dynamic>()))
          .toList(growable: false);
}

/// The tool-capability of a (provider, model): from the catalog's options, or — for `ollama` — the
/// DISCOVERED local model (P3.2). Returns `null` when the model is a custom/undiscovered id we can't
/// classify — callers WARN on `null`, never block. The **single source** shared by the picker gate and
/// the launch-time backstop, so the two can never disagree about what a run actually uses.
bool? toolCapabilityOf(
    Catalog catalog, String? provider, String? model, List<LocalModel> localModels) {
  if (provider == null || model == null || model.trim().isEmpty) return null;
  if (provider == 'ollama') {
    for (final m in localModels) {
      if (m.name == model) return m.toolCapable;
    }
  }
  for (final mode in const ['quick', 'deep']) {
    for (final o in catalog.optionsFor(provider, mode)) {
      if (o.value == model) return o.toolCapable;
    }
  }
  return null;
}
