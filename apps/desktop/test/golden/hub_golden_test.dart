import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/state/hub_provider.dart';
import 'package:quorum/state/settings_controller.dart';
import 'package:quorum/ui/hub_surface.dart';
import 'package:quorum/ui/quorum_colors.dart';
import 'package:quorum_core/quorum_core.dart';

RunSummary _run(String id, String ticker, String rating, {String mode = 'pro', double? cost = 0.42}) =>
    RunSummary(
      runId: id, status: 'done', mode: mode, ticker: ticker, tradeDate: '2026-05-10',
      provider: 'anthropic', deepModel: 'claude-opus-4-8',
      verdict: Verdict(finalDecision: '$rating $ticker', rating: rating, confidence: 0.72),
      cost: CostSnapshot(llmCalls: 14, toolCalls: 8, tokensIn: 24800, tokensOut: 13200, estUsd: cost),
    );

void main() {
  testWidgets('hub — launch, watchlist, and run history', (tester) async {
    await tester.binding.setSurfaceSize(const Size(960, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const SettingsState(
          demoMode: false, ticker: 'NVDA', provider: 'anthropic', deepModel: 'claude-opus-4-8',
          watchlist: ['NVDA', 'TSLA'],
        )),
        runHistoryProvider.overrideWith((ref) => Future.value([
              _run('r1', 'NVDA', 'Buy'),
              _run('r2', 'TSLA', 'Sell'),
              _run('r3', 'AAPL', 'Hold', mode: 'demo', cost: null),
              _run('r4', 'MSFT', 'Buy'),
            ])),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true, brightness: Brightness.dark, fontFamily: 'Inter',
          scaffoldBackgroundColor: QC.bg,
        ),
        home: const Scaffold(backgroundColor: QC.bg, body: HubSurface()),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(find.byType(HubSurface), matchesGoldenFile('goldens/hub_home.png'));
  });
}
