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
  });
}
