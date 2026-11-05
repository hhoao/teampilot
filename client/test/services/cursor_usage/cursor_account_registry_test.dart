
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_id.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_registry.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_usage_auth_resolver.dart';

import '../../support/in_memory_filesystem.dart';



void main() {
  late Filesystem fs;
  late List<CursorUsageAuth> discovered;
  late CursorAccountRegistry registry;
  final nowMs = DateTime.utc(2026, 10, 28).millisecondsSinceEpoch;

  CursorUsageAuth auth(String sub, {required int modifiedAtMs}) =>
      CursorUsageAuth(
        token: 'token-$sub',
        account: cursorAccountIdFor(sub),
        userId: 'user_01ABC',
        expiresAtMs: DateTime.utc(2027, 1, 1).millisecondsSinceEpoch,
        modifiedAtMs: modifiedAtMs,
        providerId: 'cursor',
      );


  setUp(() async {
    fs = InMemoryFilesystem();
    discovered = [auth('auth0|a', modifiedAtMs: 1)];
    registry = CursorAccountRegistry(
      fs: fs,
      accountsPath: '/root/cursor_usage/accounts.json',
      resolveAuths: () async => discovered,
    );
  });



  test('the label falls back to the provider name', () async {
    final named = CursorAccountRegistry(
      fs: fs,
      accountsPath: '/root/cursor_usage/accounts.json',
      resolveAuths: () async => discovered,
      providerNameFor: (providerId) async =>
          providerId == 'cursor' ? 'github account' : null,
    );

    final accounts = await named.list();
    expect(accounts.single.label, 'github account');
  });

  test('a manual label wins over the discovered default', () async {
    final discoveredId = cursorAccountIdFor('auth0|a');
    await registry.update(discoveredId, label: 'Team account');
    final accounts = await registry.list();
    expect(accounts.single.label, 'Team account');
  });




  test('corrupted accounts.json degrades to discovered only', () async {
    await fs.ensureDir('/root/cursor_usage');
    await fs.writeString('/root/cursor_usage/accounts.json', '{not json');
    final accounts = await registry.list();
    expect(accounts.length, 1);
  });

  test('an expired discovered account stays visible but cannot sync', () async {
    final expiredSub = 'auth0|expired';
    discovered = [
      CursorUsageAuth(
        token: 'expired-token',
        account: cursorAccountIdFor(expiredSub),
        userId: 'user_expired',
        // Expires long before the registry's clock (2026-10-28).
        expiresAtMs: DateTime.utc(2026, 10, 27).millisecondsSinceEpoch,
        modifiedAtMs: 1,
      ),
    ];

    final accounts = await registry.list();
    expect(accounts.single.accountId, cursorAccountIdFor(expiredSub));
    expect(accounts.single.isExpired(nowMs), isTrue);
    expect(
      await registry.credentialFor(cursorAccountIdFor(expiredSub)),
      isNull,
    );
  });
}
