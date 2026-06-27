// Real end-to-end S2 verification (excluded from the fast `flutter test test/` suite — lives in
// integration_test/). Uses the REAL DesktopSidecarEndpoint + real http: it spawns the actual Python
// sidecar, runs a cost-free DEMO run (no LLM, no keys), and asserts the RunViewState reaches a Buy
// verdict, then tears the sidecar down. Run with:
//   flutter test integration_test/real_run_test.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quorum/state/run_controller.dart';
import 'package:quorum_core/quorum_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('real sidecar: a demo run streams to a Buy verdict and tears down', (tester) async {
    final container = ProviderContainer(); // real endpoint + real http client
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      final ctrl = container.read(runControllerProvider.notifier);
      await ctrl.start(config: const RunConfig(mode: 'demo', ticker: 'NVDA', stepDelay: 0.1));

      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (DateTime.now().isBefore(deadline) &&
          !container.read(runControllerProvider).isTerminal) {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }

      final s = container.read(runControllerProvider);
      expect(s.phase, RunPhase.done, reason: 'run did not complete (error=${s.error})');
      expect(s.verdict?.rating, 'Buy');
      expect(s.stages[Stage.portfolio], NodeStatus.done);
      expect(s.reports.containsKey('final_trade_decision'), isTrue);

      await ctrl.shutdown();
    });
  }, timeout: const Timeout(Duration(seconds: 70)));
}
