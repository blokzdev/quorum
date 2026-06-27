/// Typed view of `GET /catalog/providers` — the provider/model catalog the engine serves from
/// `model_catalog.py`. Tolerant of missing keys so a catalog bump never hard-fails the client.
library;

class ModelOption {
  final String label;
  final String value;
  const ModelOption(this.label, this.value);

  factory ModelOption.fromJson(Map<String, dynamic> j) =>
      ModelOption(j['label'] as String? ?? '', j['value'] as String? ?? '');
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
      providers[prov as String] = ProviderCatalog(prov as String, modes);
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
