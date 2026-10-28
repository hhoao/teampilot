import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_credential_store.dart';

class _MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

String _jwt({required int exp, String sub = 'auth0|user_01ABC'}) {
  final header = base64Url
      .encode(utf8.encode('{"alg":"HS256"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'sub': sub, 'exp': exp})))
      .replaceAll('=', '');
  return '$header.$payload.signature';
}

void main() {
  final exp = DateTime.utc(2027, 1, 1).millisecondsSinceEpoch ~/ 1000;
  final nowMs = DateTime.utc(2026, 10, 28).millisecondsSinceEpoch;

  group('parseCursorSessionToken', () {
    test('accepts the bare JWT', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken(token, nowMs: nowMs);
      expect(parsed, isNotNull);
      expect(parsed!.userId, 'user_01ABC');
      expect(parsed.token, token);
      expect(parsed.accountId, cursorAccountIdFor('auth0|user_01ABC'));
      expect(parsed.expiresAtMs, exp * 1000);
    });

    test('accepts a full cookie header', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken(
        'WorkosCursorSessionToken=user_01ABC%3A%3A$token',
        nowMs: nowMs,
      );
      expect(parsed?.token, token);
      expect(parsed?.userId, 'user_01ABC');
    });

    test('accepts the userId::jwt form', () {
      final token = _jwt(exp: exp);
      final parsed = parseCursorSessionToken(
        'user_01ABC::$token',
        nowMs: nowMs,
      );
      expect(parsed?.userId, 'user_01ABC');
    });

    test('rejects a token inside the expiry guard', () {
      final token = _jwt(exp: nowMs ~/ 1000 + 10);
      expect(parseCursorSessionToken(token, nowMs: nowMs), isNull);
    });

    test('rejects garbage', () {
      expect(parseCursorSessionToken('not-a-token', nowMs: nowMs), isNull);
      expect(parseCursorSessionToken('a.b.c', nowMs: nowMs), isNull);
    });
  });

  test('accountId is the first 16 chars of sha256(sub)', () {
    final expected = sha256
        .convert(utf8.encode('auth0|user_01ABC'))
        .toString()
        .substring(0, 16);
    expect(cursorAccountIdFor('auth0|user_01ABC'), expected);
  });

  test('store round-trips credentials under a namespaced key', () async {
    final backend = _MemoryStore();
    final store = CursorAccountCredentialStore(
      store: backend,
      now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
    );
    // `read` re-parses the stored token, so the fixture has to be a real JWT
    // and its account id has to be the one derived from `sub`.
    final token = _jwt(exp: exp);
    final accountId = cursorAccountIdFor('auth0|user_01ABC');
    final credentials = CursorAccountCredentials(
      accountId: accountId,
      userId: 'user_01ABC',
      token: token,
      expiresAtMs: exp * 1000,
    );
    await store.write(credentials);
    expect(
      backend.values.keys.single,
      'teampilot.cursor_usage.v1.$accountId.token',
    );
    expect(await store.read(accountId), credentials);
    await store.delete(accountId);
    expect(await store.read(accountId), isNull);
  });
}
