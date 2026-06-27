import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quorum/services/key_vault.dart';

/// flutter_secure_storage's platform MethodChannel. We back it with an in-memory map so tests never
/// touch the real OS Credential Manager (and never leak a key into CI).
const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, String> store;

  setUp(() {
    store = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? const {};
      switch (call.method) {
        case 'write':
          store[args['key'] as String] = args['value'] as String;
          return null;
        case 'read':
          return store[args['key'] as String];
        case 'delete':
          store.remove(args['key'] as String);
          return null;
        case 'readAll':
          return Map<String, String>.from(store);
        case 'deleteAll':
          store.clear();
          return null;
        case 'containsKey':
          return store.containsKey(args['key'] as String);
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('writes/reads per-provider entries under quorum_apikey_<provider>', () async {
    final vault = KeyVault();
    await vault.write('Google', 'g-key'); // provider name is lowercased
    await vault.write('anthropic', 'a-key');
    expect(store['quorum_apikey_google'], 'g-key');
    expect(store['quorum_apikey_anthropic'], 'a-key');
    expect(await vault.read('google'), 'g-key');
    expect(await vault.readAll(), {'google': 'g-key', 'anthropic': 'a-key'});
  });

  test('forgetAll deletes only quorum_apikey_* entries, leaving others intact', () async {
    final vault = KeyVault();
    await vault.write('google', 'g-key');
    store['unrelated_credential'] = 'keep-me';
    await vault.forgetAll();
    expect(store.containsKey('quorum_apikey_google'), isFalse);
    expect(store['unrelated_credential'], 'keep-me');
  });
}
