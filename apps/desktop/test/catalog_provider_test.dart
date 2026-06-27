import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quorum/state/catalog_provider.dart';
import 'package:quorum/state/run_controller.dart';
import 'package:quorum_core/quorum_core.dart';

class _FakeEndpoint implements EngineEndpoint {
  @override
  Future<EngineConnection> connect() async =>
      EngineConnection(Uri.parse('http://127.0.0.1:65000'), 'tok');
  @override
  Future<void> dispose() async {}
}

const _catalogBody =
    '{"contract_version":1,"providers":{"anthropic":{"quick":[{"label":"Sonnet 4.6","value":"claude-sonnet-4-6"}],'
    '"deep":[{"label":"Opus 4.8","value":"claude-opus-4-8"}]}},"analysts":["market","news"]}';

void main() {
  test('Catalog.fromJson parses providers/modes/options + analysts (tolerant)', () {
    final cat = Catalog.fromJson(jsonDecode(_catalogBody) as Map<String, dynamic>);
    expect(cat.contractVersion, 1);
    expect(cat.providerNames, contains('anthropic'));
    expect(cat.optionsFor('anthropic', 'deep').single.value, 'claude-opus-4-8');
    expect(cat.optionsFor('anthropic', 'quick').single.label, 'Sonnet 4.6');
    expect(cat.analysts, ['market', 'news']);
    // missing provider/mode -> empty, never throws
    expect(cat.optionsFor('nope', 'deep'), isEmpty);
  });

  test('catalogProvider fetches + parses the live catalog (lazy, bearer-authed)', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/catalog/providers') {
        if (req.headers['authorization'] != 'Bearer tok') return http.Response('unauth', 401);
        return http.Response(_catalogBody, 200);
      }
      return http.Response('not found', 404);
    });
    final c = ProviderContainer(overrides: [
      engineEndpointProvider.overrideWithValue(_FakeEndpoint()),
      httpClientProvider.overrideWithValue(client),
    ]);
    addTearDown(c.dispose);

    final cat = await c.read(catalogProvider.future);
    expect(cat.providerNames, contains('anthropic'));
    expect(cat.optionsFor('anthropic', 'quick').single.value, 'claude-sonnet-4-6');
  });
}
