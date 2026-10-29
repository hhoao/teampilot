import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_credential_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_registry.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_usage_auth_resolver.dart';

import '../../support/in_memory_filesystem.dart';

class _MemoryStore implements SecureKeyValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

String _jwt({required String sub, required int exp}) {
  String enc(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${enc({'alg': 'none'})}.${enc({'sub': sub, 'exp': exp})}.sig';
}

void main() {
  late Filesystem fs;
  late _MemoryStore backend;
  late List<CursorUsageAuth> discovered;
  late CursorAccountRegistry registry;
  final nowMs = DateTime.utc(2026, 10, 28).millisecondsSinceEpoch;
  final manualExpSeconds =
      DateTime.utc(2027, 2, 1).millisecondsSinceEpoch ~/ 1000;

  CursorUsageAuth auth(String sub, {required int modifiedAtMs}) =>
      CursorUsageAuth(
        token: 'token-$sub',
        account: cursorAccountIdFor(sub),
        userId: 'user_01ABC',
        expiresAtMs: DateTime.utc(2027, 1, 1).millisecondsSinceEpoch,
        modifiedAtMs: modifiedAtMs,
      );

  // `CursorAccountCredentialStore.read` re-parses the stored token, so manual
  // fixtures have to be real JWTs whose `sub` derives the same account id.
  CursorAccountCredentials manualCredentials() {
    const sub = 'auth0|user_02DEF';
    return CursorAccountCredentials(
      accountId: cursorAccountIdFor(sub),
      userId: 'user_02DEF',
      token: _jwt(sub: sub, exp: manualExpSeconds),
      expiresAtMs: manualExpSeconds * 1000,
    );
  }

  setUp(() async {
    fs = InMemoryFilesystem();
    backend = _MemoryStore();
    discovered = [auth('auth0|a', modifiedAtMs: 1)];
    registry = CursorAccountRegistry(
      fs: fs,
      accountsPath: '/root/cursor_usage/accounts.json',
      // The clock that governs token validity lives in the credential store;
      // the registry never reads one.
      credentials: CursorAccountCredentialStore(
        store: backend,
        now: () => DateTime.fromMillisecondsSinceEpoch(nowMs),
      ),
      resolveAuths: () async => discovered,
    );
  });

  test('lists discovered accounts with hasCredential true', () async {
    final accounts = await registry.list();
    expect(accounts.length, 1);
    expect(accounts.single.accountId, cursorAccountIdFor('auth0|a'));
    expect(accounts.single.source, CursorAccountSource.discovered);
    expect(accounts.single.hasCredential, isTrue);
  });

  test('manual entry adds a second account and is readable back', () async {
    final credentials = manualCredentials();
    await registry.upsertManual(credentials, label: 'Work');

    final accounts = await registry.list();
    expect(accounts.length, 2);
    final manual = accounts.firstWhere(
      (account) => account.accountId == credentials.accountId,
    );
    expect(manual.source, CursorAccountSource.manual);
    expect(manual.label, 'Work');
    expect(manual.hasCredential, isTrue);
    expect(await registry.credentialFor(credentials.accountId), credentials);
  });

  test('a manual label wins over the discovered default', () async {
    final discoveredId = cursorAccountIdFor('auth0|a');
    await registry.update(discoveredId, label: 'Team account');
    final accounts = await registry.list();
    expect(accounts.single.label, 'Team account');
  });

  test('removing a manual account also drops its secret', () async {
    final credentials = manualCredentials();
    await registry.upsertManual(credentials);
    await registry.remove(credentials.accountId);
    expect(await registry.credentialFor(credentials.accountId), isNull);
    expect(backend.values.keys, isEmpty);
  });

  test('re-pasting a token keeps the stored team and enabled state', () async {
    final credentials = manualCredentials();
    await registry.upsertManual(credentials, label: 'Team', teamId: 7);
    await registry.update(credentials.accountId, enabled: false);

    // A rotated token is pasted with no label and no team: only the credential
    // may change, everything the user configured has to survive.
    await registry.upsertManual(credentials);

    final account = (await registry.list()).firstWhere(
      (entry) => entry.accountId == credentials.accountId,
    );
    expect(account.teamId, 7);
    expect(account.enabled, isFalse);
    expect(account.label, 'Team');
  });

  test('accounts.json holds metadata only, never the token', () async {
    final credentials = manualCredentials();
    await registry.upsertManual(credentials, label: 'Work');

    final raw = await fs.readString('/root/cursor_usage/accounts.json');
    expect(raw, isNotNull);
    expect(raw, isNot(contains(credentials.token)));
  });

  test('corrupted accounts.json degrades to discovered only', () async {
    await fs.ensureDir('/root/cursor_usage');
    await fs.writeString('/root/cursor_usage/accounts.json', '{not json');
    final accounts = await registry.list();
    expect(accounts.length, 1);
    expect(accounts.single.source, CursorAccountSource.discovered);
  });
}
