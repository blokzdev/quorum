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
