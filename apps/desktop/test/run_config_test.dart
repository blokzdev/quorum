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

    test('agent_models (Dream Team) round-trips under exact snake_case keys; omitted when null', () {
      expect(const RunConfig(mode: 'pro').toJson().containsKey('agent_models'), isFalse);
      const cfg = RunConfig(mode: 'pro', ticker: 'NVDA', agentModels: {
        'portfolio_manager': AgentModel(provider: 'anthropic', model: 'claude-opus-4-8', effort: 'high'),
        'market_analyst':
            AgentModel(provider: 'ollama', model: 'llama3.2:latest', backendUrl: 'http://localhost:11434/v1'),
      });
      final j = cfg.toJson();
      expect(j['agent_models']['portfolio_manager'],
          {'provider': 'anthropic', 'model': 'claude-opus-4-8', 'effort': 'high'});
      expect(j['agent_models']['market_analyst'],
          {'provider': 'ollama', 'model': 'llama3.2:latest', 'backend_url': 'http://localhost:11434/v1'});
      final back = RunConfig.fromJson(j);
      expect(back.agentModels!['portfolio_manager'],
          const AgentModel(provider: 'anthropic', model: 'claude-opus-4-8', effort: 'high'));
      expect(back.agentModels!['market_analyst']!.backendUrl, 'http://localhost:11434/v1');
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

    test('per-provider effort knobs round-trip under exact snake_case keys; omitted when null', () {
      const cfg = RunConfig(
        mode: 'pro',
        provider: 'google',
        googleThinkingLevel: 'high',
        openaiReasoningEffort: 'medium',
        anthropicEffort: 'low',
      );
      final j = cfg.toJson();
      expect(j['google_thinking_level'], 'high');
      expect(j['openai_reasoning_effort'], 'medium');
      expect(j['anthropic_effort'], 'low');

      final bare = const RunConfig(mode: 'demo').toJson();
      expect(bare.containsKey('google_thinking_level'), isFalse);
      expect(bare.containsKey('openai_reasoning_effort'), isFalse);
      expect(bare.containsKey('anthropic_effort'), isFalse);
    });

    test('fromJson(toJson(cfg)) round-trips the fields', () {
      const cfg = RunConfig(
        mode: 'pro',
        ticker: 'TSLA',
        provider: 'google',
        deepModel: 'gemini-3.1-pro-preview',
        quickModel: 'gemini-3.5-flash',
        googleThinkingLevel: 'high',
        researchDepth: 2,
        backendUrl: 'https://x',
        apiKeys: {'google': 'k'},
      );
      final back = RunConfig.fromJson(cfg.toJson());
      expect(back.mode, 'pro');
      expect(back.ticker, 'TSLA');
      expect(back.provider, 'google');
      expect(back.deepModel, 'gemini-3.1-pro-preview');
      expect(back.quickModel, 'gemini-3.5-flash');
      expect(back.googleThinkingLevel, 'high');
      expect(back.researchDepth, 2);
      expect(back.backendUrl, 'https://x');
      expect(back.apiKeys, {'google': 'k'});
    });

    test('data_vendors round-trips (P3.1); empty map is omitted', () {
      const cfg = RunConfig(
        mode: 'pro',
        ticker: 'AAPL',
        dataVendors: {'core_stock_apis': 'alpha_vantage', 'news_data': 'alpha_vantage'},
      );
      final json = cfg.toJson();
      expect(json['data_vendors'], {'core_stock_apis': 'alpha_vantage', 'news_data': 'alpha_vantage'});
      expect(RunConfig.fromJson(json).dataVendors,
          {'core_stock_apis': 'alpha_vantage', 'news_data': 'alpha_vantage'});
      // Empty/absent → omitted from the wire (keeps the body clean; engine uses defaults).
      expect(const RunConfig(mode: 'pro').toJson().containsKey('data_vendors'), isFalse);
      expect(const RunConfig(mode: 'pro', dataVendors: {}).toJson().containsKey('data_vendors'), isFalse);
    });
  });

  group('VendorCatalog.fromJson (P3.1 /catalog/vendors)', () {
    test('parses categories, optional flag, default, and per-vendor key needs', () {
      final vc = VendorCatalog.fromJson({
        'contract_version': 1,
        'categories': [
          {
            'key': 'core_stock_apis',
            'label': 'OHLCV stock price data',
            'optional': false,
            'default': 'yfinance',
            'vendors': [
              {'value': 'yfinance', 'needs_key': false, 'key_env': null},
              {'value': 'alpha_vantage', 'needs_key': true, 'key_env': 'ALPHA_VANTAGE_API_KEY'},
            ],
          },
          {'key': 'macro_data', 'label': 'Macro', 'optional': true, 'default': 'fred', 'vendors': []},
        ],
      });
      final core = vc.categoryFor('core_stock_apis')!;
      expect(core.optional, isFalse);
      expect(core.defaultVendor, 'yfinance');
      final av = core.vendors.firstWhere((v) => v.value == 'alpha_vantage');
      expect(av.needsKey, isTrue);
      expect(av.keyEnv, 'ALPHA_VANTAGE_API_KEY');
      expect(vc.categoryFor('macro_data')!.optional, isTrue);
      expect(vc.categoryFor('nope'), isNull);
    });
  });
}
