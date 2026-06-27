import 'package:flutter_test/flutter_test.dart';
import 'package:quorum_core/quorum_core.dart';

void main() {
  group('RunConfig.toJson() (pins the services/api/app.py RunRequest contract)', () {
    test('demo default reproduces the historical payload + explicit safe defaults', () {
      const cfg = RunConfig(mode: 'demo', ticker: 'NVDA', stepDelay: 0.2);
      expect(cfg.toJson(), {
        'mode': 'demo',
        'research_depth': 1,
        'output_language': 'English',
        'ticker': 'NVDA',
        'step_delay': 0.2,
      });
    });

    test('mode is always emitted (sidecar defaults to vibe; omitting flips demo -> real run)', () {
      expect(const RunConfig().toJson()['mode'], 'demo');
      expect(const RunConfig(mode: 'pro').toJson()['mode'], 'pro');
    });

    test('null fields are omitted; set fields use the exact snake_case keys', () {
      const cfg = RunConfig(
        mode: 'pro',
        ticker: 'TSLA',
        tradeDate: '2026-06-26',
        assetType: 'stock',
        analysts: ['market', 'news'],
        researchDepth: 3,
        provider: 'anthropic',
        deepModel: 'claude-opus-4-8',
        quickModel: 'claude-haiku-4-5',
        backendUrl: 'https://x',
        apiKeys: {'anthropic': 'sk-x'},
      );
      final j = cfg.toJson();
      expect(j['trade_date'], '2026-06-26');
      expect(j['asset_type'], 'stock');
      expect(j['analysts'], ['market', 'news']);
      expect(j['research_depth'], 3);
      expect(j['provider'], 'anthropic');
      expect(j['deep_model'], 'claude-opus-4-8');
      expect(j['quick_model'], 'claude-haiku-4-5');
      expect(j['backend_url'], 'https://x');
      expect(j['api_keys'], {'anthropic': 'sk-x'});
      // omitted when null
      expect(j.containsKey('step_delay'), isFalse);
      expect(j.containsKey('intent'), isFalse);
    });

    test('copyWith overrides only the given fields', () {
      const base = RunConfig(mode: 'demo', ticker: 'NVDA');
      final next = base.copyWith(mode: 'pro', provider: 'google');
      expect(next.mode, 'pro');
      expect(next.ticker, 'NVDA');
      expect(next.provider, 'google');
    });
  });
}
