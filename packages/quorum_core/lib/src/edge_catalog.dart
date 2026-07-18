/// Typed view of `GET /catalog/edge-models` — the curated Edge Model Draft Board (P5.1a). Tolerant
/// of missing keys like [Catalog]/[VendorCatalog], so a catalog bump never hard-fails the client.
library;

import 'catalog.dart' show LocalModel;
import 'device_fit.dart';

/// Which agent roles a curated model can serve. [analyst] = tool-capable through Ollama;
/// [textOnly] = debate/judge roles only (e.g. a model whose tool-calling Ollama can't reach);
/// [unknown] = an unrecognized server string (forward-compat — the UI treats it as textOnly-safe).
enum EdgeRoleCapability { analyst, textOnly, unknown }

/// One curated Draft Board entry. [bytes] is the EXACT registry model-layer size (the P5.2c pull
/// drift-tripwire input); [kvParams] are the raw KV-formula inputs so the client computes KV at
/// [kDefaultOllamaCtx] (a raised ctx is a one-constant change — plan A6).
class EdgeModel {
  final String id;
  final String ollamaTag;
  final String display;
  final int? bytes;
  final Map<String, int> kvParams;
  final EdgeRoleCapability capability;
  final String license;
  final String blurb;

  /// P5.4a honesty status: `real-run` | `tag-only` | `none` (raw server string; unknown tolerated).
  final String verified;
  final bool isDefault;

  /// Minimum Ollama version this entry needs (e.g. qwen3.5 tool parsing needs `0.17.6`; gemma4's
  /// registry declares `0.20.0`); null = no known floor. Feeds the P5.1d per-entry version gate.
  final String? minOllamaVersion;

  const EdgeModel({
    required this.id,
    required this.ollamaTag,
    required this.display,
    required this.bytes,
    required this.kvParams,
    required this.capability,
    required this.license,
    required this.blurb,
    required this.verified,
    required this.isDefault,
    required this.minOllamaVersion,
  });

  factory EdgeModel.fromJson(Map<String, dynamic> j) {
    final capRaw = j['capability'] as String? ?? '';
    final kv = <String, int>{};
    ((j['kv_params'] as Map?) ?? const {}).forEach((k, v) {
      if (v is num) kv[k as String] = v.toInt();
    });
    return EdgeModel(
      id: j['id'] as String? ?? '',
      ollamaTag: j['ollama_tag'] as String? ?? '',
      display: j['display'] as String? ?? (j['ollama_tag'] as String? ?? ''),
      bytes: (j['bytes'] as num?)?.toInt(),
      kvParams: kv,
      capability: switch (capRaw) {
        'analyst' => EdgeRoleCapability.analyst,
        'text_only' => EdgeRoleCapability.textOnly,
        _ => EdgeRoleCapability.unknown,
      },
      license: j['license'] as String? ?? '',
      blurb: j['blurb'] as String? ?? '',
      verified: j['verified'] as String? ?? '',
      isDefault: j['default'] as bool? ?? false,
      minOllamaVersion: j['min_ollama_version'] as String?,
    );
  }

  /// KV bytes at [ctx] from the served params — null when any input is missing (a missing number
  /// never fabricates a fit verdict).
  int? kvBytesAt({int ctx = kDefaultOllamaCtx}) {
    final b = kvParams['block_count'], h = kvParams['head_count_kv'];
    final k = kvParams['key_length'], v = kvParams['value_length'];
    if (b == null || h == null || k == null || v == null) return null;
    return kvBytes(blockCount: b, headCountKv: h, keyLength: k, valueLength: v, ctx: ctx);
  }

  /// The badge for this entry on a device with [deviceRamMb] reported RAM — null when the catalog
  /// lacks bytes/KV data or RAM is unknown (UI renders an explicit Unknown state, never a guess).
  /// [ctx] should be the CATALOG's served `kv_ctx` (so a hosted re-tier that raises the context is
  /// honored by old clients too — the review caught that parsing kvCtx without consuming it made the
  /// drift guard a no-op); defaults to [kDefaultOllamaCtx].
  FitBadge? fitBadgeFor(int? deviceRamMb, {int ctx = kDefaultOllamaCtx}) {
    final b = bytes, kv = kvBytesAt(ctx: ctx);
    if (b == null || kv == null || deviceRamMb == null) return null;
    return fitBadge(modelBytes: b, kvBytes: kv, deviceRamMb: deviceRamMb);
  }
}

/// One tier group: its floor (MiB, decimal-thousand — see [kCoreTierFloorMb]) + its curated models.
class EdgeTier {
  final String tierRaw;
  final int minDeviceRamMb;
  final List<EdgeModel> models;
  const EdgeTier({required this.tierRaw, required this.minDeviceRamMb, required this.models});

  /// Parsed tier; null on an unrecognized server string (forward-compat — bucketed nowhere).
  DeviceTier? get tier => switch (tierRaw) {
        'lite' => DeviceTier.lite,
        'core' => DeviceTier.core,
        'max' => DeviceTier.max,
        _ => null,
      };

  EdgeModel? get defaultModel {
    for (final m in models) {
      if (m.isDefault) return m;
    }
    return null;
  }

  factory EdgeTier.fromJson(Map<String, dynamic> j) => EdgeTier(
        tierRaw: j['tier'] as String? ?? '',
        minDeviceRamMb: (j['min_device_ram_mb'] as num?)?.toInt() ?? 0,
        models: ((j['models'] as List?) ?? const [])
            .map((m) => EdgeModel.fromJson((m as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );
}

class EdgeModelCatalog {
  final int contractVersion;
  final int catalogVersion;

  /// The detected Ollama version — null = Ollama absent/unreachable (the P5.3c onboarding
  /// discriminator and the P5.1d version-gate input).
  final String? ollamaVersion;

  /// The ctx the server's curation assumed — a visible drift guard vs [kDefaultOllamaCtx].
  final int kvCtx;
  final List<EdgeTier> tiers;

  const EdgeModelCatalog({
    this.contractVersion = 0,
    this.catalogVersion = 0,
    this.ollamaVersion,
    this.kvCtx = kDefaultOllamaCtx,
    this.tiers = const [],
  });

  factory EdgeModelCatalog.fromJson(Map<String, dynamic> j) => EdgeModelCatalog(
        contractVersion: (j['contract_version'] as num?)?.toInt() ?? 0,
        catalogVersion: (j['catalog_version'] as num?)?.toInt() ?? 0,
        ollamaVersion: j['ollama_version'] as String?,
        kvCtx: (j['kv_ctx'] as num?)?.toInt() ?? kDefaultOllamaCtx,
        tiers: ((j['tiers'] as List?) ?? const [])
            .map((t) => EdgeTier.fromJson((t as Map).cast<String, dynamic>()))
            .toList(growable: false),
      );

  EdgeTier? forTier(DeviceTier t) {
    for (final tier in tiers) {
      if (tier.tier == t) return tier;
    }
    return null;
  }

  /// The curated entry whose tag canonically matches [tag] (P5.3b roster-fit lookup) — null when the
  /// tag isn't on the Draft Board (a discovered/custom model; the caller must not fabricate numbers).
  EdgeModel? entryForTag(String tag) {
    if (tag.isEmpty) return null;
    final wanted = canonicalTag(tag);
    for (final tier in tiers) {
      for (final m in tier.models) {
        if (m.ollamaTag.isNotEmpty && canonicalTag(m.ollamaTag) == wanted) return m;
      }
    }
    return null;
  }
}

/// Ollama normalizes bare tags to `:latest` (`llama3.2` ⇄ `llama3.2:latest`) — the shared canonical
/// form for tag equality, so `qwen3.5:2b` ≠ `qwen3.5:0.8b` but a bare name matches its `:latest`.
String canonicalTag(String tag) => tag.contains(':') ? tag : '$tag:latest';

/// Whether a curated entry is already pulled, per the device's discovery list (canonical-tag match).
bool isInstalled(EdgeModel entry, List<LocalModel> localModels) {
  final tag = entry.ollamaTag;
  if (tag.isEmpty) return false;
  final expanded = canonicalTag(tag);
  for (final m in localModels) {
    if (canonicalTag(m.name) == expanded) return true;
  }
  return false;
}

/// Numeric dotted-segment version compare — NOT lexicographic (`'0.9.5' < '0.17.6'`, but string
/// compare says 9 > 1). Returns false when [detected] is null (Ollama absent) or unparseable —
/// callers gate/warn (P5.1d), never grant on garbage.
bool ollamaVersionAtLeast(String? detected, String required) {
  if (detected == null) return false;
  List<int>? parse(String s) {
    final parts = s.trim().split('.');
    final out = <int>[];
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out.isEmpty ? null : out;
  }

  final d = parse(detected), r = parse(required);
  if (d == null || r == null) return false;
  for (var i = 0; i < r.length; i++) {
    final dv = i < d.length ? d[i] : 0;
    if (dv > r[i]) return true;
    if (dv < r[i]) return false;
  }
  return true;
}
