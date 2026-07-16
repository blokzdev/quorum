// P5.1b — the device's total RAM + derived tier (Lite/Core/Max). The ONLY impure piece of the
// device-fit stack: the plugin read lives here; all math is pure quorum_core (device_fit.dart).
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quorum_core/quorum_core.dart';

/// Total physical RAM in MiB (`device_info_plus` → Windows `systemMemoryInMegabytes`, sourced from
/// `GlobalMemoryStatusEx` — reports *usable* RAM, ~0.3–1GiB under nominal, which is exactly why the
/// tier floors are decimal-thousand MiB). `null` on any failure or non-Windows host — consumers
/// degrade to "fit unknown", never throw.
final deviceRamMbProvider = FutureProvider<int?>((ref) async {
  try {
    final info = await DeviceInfoPlugin().windowsInfo;
    final mb = info.systemMemoryInMegabytes;
    return mb > 0 ? mb : null;
  } catch (_) {
    return null;
  }
});

/// The device's Draft Board tier; `null` while loading or when RAM is unreadable.
final deviceTierProvider = Provider<DeviceTier?>((ref) {
  final mb = ref.watch(deviceRamMbProvider).value;
  return mb == null ? null : deviceTier(mb);
});
