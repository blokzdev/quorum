// P5.1b — RAM→tier provider mapping via override injection (the plugin read itself is an untested
// one-liner by design; the mapping is the logic).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/device_ram_provider.dart';
import 'package:quorum_core/quorum_core.dart';

void main() {
  test('16GB device derives the core tier', () async {
    final c = ProviderContainer(overrides: [
      deviceRamMbProvider.overrideWith((ref) async => 16384),
    ]);
    addTearDown(c.dispose);
    await c.read(deviceRamMbProvider.future);
    expect(c.read(deviceTierProvider), DeviceTier.core);
  });

  test('a physical 32GB machine reporting 31.7GiB usable derives MAX (the A2 decimal-floor rule)',
      () async {
    final c = ProviderContainer(overrides: [
      deviceRamMbProvider.overrideWith((ref) async => 32460),
    ]);
    addTearDown(c.dispose);
    await c.read(deviceRamMbProvider.future);
    expect(c.read(deviceTierProvider), DeviceTier.max);
  });

  test('unreadable RAM (null) derives a null tier — fit unknown, never a guess', () async {
    final c = ProviderContainer(overrides: [
      deviceRamMbProvider.overrideWith((ref) async => null),
    ]);
    addTearDown(c.dispose);
    await c.read(deviceRamMbProvider.future);
    expect(c.read(deviceTierProvider), isNull);
  });
}
