import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Per-provider BYO API-key vault backed by the OS credential store (Windows Credential Manager /
/// macOS Keychain) via `flutter_secure_storage`. One entry per provider — `quorum_apikey_<provider>`,
/// never a single JSON blob (Windows Credential Manager caps a credential blob at 2560 bytes; see
/// [ADR 0001](../../../../docs/decisions/0001-byo-api-key-storage.md)).
///
/// Keys are **never logged** and never leave this service except into a run's request body at launch
/// (and only for a non-demo run). The macOS port needs no code change.
class KeyVault {
  static const _prefix = 'quorum_apikey_';

  final FlutterSecureStorage _storage;
  KeyVault({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  String _entry(String provider) => '$_prefix${provider.toLowerCase()}';

  Future<String?> read(String provider) => _storage.read(key: _entry(provider));

  Future<void> write(String provider, String key) =>
      _storage.write(key: _entry(provider), value: key);

  Future<void> delete(String provider) => _storage.delete(key: _entry(provider));

  /// Every stored provider key as `{provider: key}` — only this app's `quorum_apikey_*` entries.
  Future<Map<String, String>> readAll() async {
    final all = await _storage.readAll();
    final out = <String, String>{};
    for (final e in all.entries) {
      if (e.key.startsWith(_prefix)) out[e.key.substring(_prefix.length)] = e.value;
    }
    return out;
  }

  /// Delete only this app's `quorum_apikey_*` entries; unrelated OS credentials are left intact.
  Future<void> forgetAll() async {
    final all = await _storage.readAll();
    for (final k in all.keys) {
      if (k.startsWith(_prefix)) await _storage.delete(key: k);
    }
  }
}

/// The shared key vault. Override in tests with a `KeyVault` over a mocked secure-storage channel.
final keyVaultProvider = Provider<KeyVault>((ref) => KeyVault());
