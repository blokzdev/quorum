/// P5.3b roster-fit — "can this machine run my whole Dream Team?" as pure arithmetic.
///
/// Correctness note (plan-locked): Ollama loads models per-request and swaps them (default
/// `OLLAMA_MAX_LOADED_MODELS`), so roster RAM fit = **the max single model + its KV**, NOT the sum.
/// A roster spanning several distinct local models still fits if the largest fits — it just pays a
/// swap-latency cost, surfaced as [RosterFitResult.swapLatencyNote], never as a fit failure.
///
/// Honesty posture (matches the badge math in `edge_catalog.dart`): a number we don't have is never
/// fabricated. A non-curated tag contributes at best a bytes-only lower bound (discovery reports blob
/// size but no KV geometry) — enough to prove *wontFit* honestly, never enough to promise *fits*.
library;

import 'agent_model.dart';
import 'catalog.dart' show LocalModel;
import 'device_fit.dart';
import 'edge_catalog.dart';

/// Distinct-local-model count at/above which the swap-latency note shows. Named so re-tuning is a
/// data change, not a rewrite (the A6 rule).
const int kSwapNoteThreshold = 2;

class RosterFitResult {
  /// The fit verdict for the roster's largest local model — null = honestly unknown (missing sizes,
  /// unknown device RAM, or no local slots at all). A null verdict with [unknownTags] populated is
  /// "can't promise", not "doesn't fit"; wontFit is only reported when even understated numbers fail.
  final FitBadge? verdict;

  /// The tag with the largest known RAM requirement (bytes + KV, or the bytes-only bound).
  final String? limitingTag;

  /// That requirement in bytes (understated when [limitingTag] is a bytes-only bound).
  final int? limitingBytes;

  /// Whether [limitingBytes] includes the KV term (a complete curated number) — false for a
  /// bytes-only bound, so UI copy can say "at least X GB" instead of falsely claiming the number
  /// covers context memory (#54 review).
  final bool limitingIncludesKv;

  /// Distinct canonical ollama tags across the roster's effective slots.
  final int distinctLocalModels;

  /// True when the roster spans [kSwapNoteThreshold]+ distinct local models (per-request swap cost).
  final bool swapLatencyNote;

  /// Tags that contributed no *complete* number: non-curated installed tags (bytes-only bound, no KV
  /// geometry) and tags with no known size at all (uninstalled custom tags).
  final List<String> unknownTags;

  const RosterFitResult({
    required this.verdict,
    required this.limitingTag,
    required this.limitingBytes,
    this.limitingIncludesKv = false,
    required this.distinctLocalModels,
    required this.swapLatencyNote,
    required this.unknownTags,
  });
}

/// Expand a Dream Team roster into its effective per-role slots: the role's override, else the
/// global provider with the deep model for [deepRoles] and the quick model otherwise. Callers pass
/// RESOLVED model names (the `custom` sentinel already swapped for its custom text). A role that
/// resolves to no provider or a blank model contributes nothing — fit can only reason about slots
/// that would actually run.
List<AgentModel> effectiveSlots({
  required Iterable<String> roleKeys,
  required Set<String> deepRoles,
  Map<String, AgentModel>? agentModels,
  String? globalProvider,
  String? quickModel,
  String? deepModel,
}) {
  final out = <AgentModel>[];
  for (final role in roleKeys) {
    final override = agentModels?[role];
    // A present-but-malformed override (blank provider/model) is UNASSIGNED to the engine — it
    // falls back to the global quick/deep model for that role — so it must fall through here too,
    // not silently contribute nothing (#54 review: fit would miss the model that actually runs).
    if (override != null && override.provider.isNotEmpty && override.model.trim().isNotEmpty) {
      out.add(override);
      continue;
    }
    final provider = globalProvider;
    if (provider == null || provider.isEmpty) continue;
    final model = deepRoles.contains(role) ? deepModel : quickModel;
    if (model == null || model.trim().isEmpty) continue;
    out.add(AgentModel(provider: provider, model: model));
  }
  return out;
}

/// Whether an OpenAI-compatible base URL points at THIS machine. A slot served by a remote Ollama
/// must not be charged against local RAM (#54 review) — an unparseable/empty URL reads as local
/// (the provider default is localhost).
bool isLoopbackBackendUrl(String? url) {
  if (url == null || url.trim().isEmpty) return true;
  final host = Uri.tryParse(url.trim())?.host ?? '';
  if (host.isEmpty) return true;
  return host == 'localhost' || host == '127.0.0.1' || host == '::1' || host == '[::1]';
}

/// The roster-fit verdict for [slots] on a device with [deviceRamMb] reported RAM. [ctx] defaults to
/// the catalog's served `kv_ctx` (a hosted re-tier that raises the context is honored).
RosterFitResult rosterFit({
  required Iterable<AgentModel> slots,
  required EdgeModelCatalog catalog,
  required List<LocalModel> localModels,
  required int? deviceRamMb,
  int? ctx,
}) {
  final effCtx = ctx ?? catalog.kvCtx;

  // Distinct canonical local tags — the swap-note count and the per-model fit universe. A slot
  // pinned to a REMOTE Ollama (per-role backendUrl) never loads locally — excluded (#54 review).
  final tags = <String>{};
  for (final s in slots) {
    if (s.provider.toLowerCase() != 'ollama') continue;
    if (!isLoopbackBackendUrl(s.backendUrl)) continue;
    final tag = s.model.trim();
    if (tag.isEmpty) continue;
    tags.add(canonicalTag(tag));
  }

  final unknown = <String>[];
  String? limitingTag;
  int? limitingBytes;
  var limitingComplete = false; // does the limiting number include KV?

  for (final tag in tags) {
    final entry = catalog.entryForTag(tag);
    final bytes = entry?.bytes;
    final kv = entry?.kvBytesAt(ctx: effCtx);
    int? requirement;
    var complete = false;
    if (bytes != null && kv != null) {
      requirement = bytes + kv; // curated: exact registry bytes + KV at the effective ctx
      complete = true;
    } else {
      // Bytes-only lower bound: a curated row's served bytes even when its KV geometry is broken
      // (#54 review — provable wontFit must not degrade to silence), else the installed blob
      // size. Either is enough to prove wontFit, never enough to promise fits.
      requirement = bytes;
      if (requirement == null) {
        for (final m in localModels) {
          if (canonicalTag(m.name) == tag && m.size != null) {
            requirement = m.size;
            break;
          }
        }
      }
      unknown.add(tag);
    }
    if (requirement != null && (limitingBytes == null || requirement > limitingBytes)) {
      limitingTag = tag;
      limitingBytes = requirement;
      limitingComplete = complete;
    }
  }

  FitBadge? verdict;
  if (limitingBytes != null && deviceRamMb != null) {
    // Max-not-sum: only the single largest requirement is resident at once.
    final badge = fitBadge(modelBytes: limitingBytes, kvBytes: 0, deviceRamMb: deviceRamMb);
    if (badge == FitBadge.wontFit) {
      verdict = FitBadge.wontFit; // even an understated number already fails — honest fail
    } else if (unknown.isEmpty && limitingComplete) {
      verdict = badge; // every slot fully known → the badge is a promise we can keep
    }
    // else: incomplete data that doesn't already fail → verdict stays null ("can't promise").
  }

  return RosterFitResult(
    verdict: verdict,
    limitingTag: limitingTag,
    limitingBytes: limitingBytes,
    limitingIncludesKv: limitingComplete,
    distinctLocalModels: tags.length,
    swapLatencyNote: tags.length >= kSwapNoteThreshold,
    unknownTags: List.unmodifiable(unknown),
  );
}
