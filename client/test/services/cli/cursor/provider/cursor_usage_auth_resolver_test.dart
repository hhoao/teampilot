import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_usage_auth_resolver.dart';

import '../../../../support/in_memory_filesystem.dart';

String _jwt({required String sub, required int exp}) {
  String enc(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${enc({'alg': 'none'})}.${enc({'sub': sub, 'exp': exp})}.sig';
}

void main() {
  final now = DateTime.utc(2026, 10, 28, 12);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  test('prefers a live provider token over an expired global token', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/cursor/provider-1/home/.config/cursor/auth.json',
      jsonEncode({
        'accessToken': _jwt(sub: 'user|provider-user', exp: nowSeconds + 3600),
        'refreshToken': 'refresh',
      }),
    );
    await fs.writeString(
      '/home/test/.config/cursor/auth.json',
      jsonEncode({
        'accessToken': _jwt(sub: 'user|expired-user', exp: nowSeconds - 60),
      }),
    );

    final auth = await CursorUsageAuthResolver(
      fs: fs,
      basePath: '/tp',
      home: '/home/test',
      now: () => now,
    ).resolve();

    expect(auth, isNotNull);
    expect(auth!.userId, 'provider-user');
    expect(
      auth.cookie,
      startsWith('WorkosCursorSessionToken=provider-user%3A%3A'),
    );
  });

  test('returns null when every token is expired', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/home/test/.config/cursor/auth.json',
      jsonEncode({'accessToken': _jwt(sub: 'user|old', exp: nowSeconds - 1)}),
    );

    final auth = await CursorUsageAuthResolver(
      fs: fs,
      basePath: '/tp',
      home: '/home/test',
      now: () => now,
    ).resolve();

    expect(auth, isNull);
  });

  test('includeExpired surfaces expired tokens for display', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/tp/providers/cursor/provider-1/home/.config/cursor/auth.json',
      jsonEncode({
        'accessToken': _jwt(sub: 'user|old', exp: nowSeconds - 3600),
      }),
    );

    final resolver = CursorUsageAuthResolver(
      fs: fs,
      basePath: '/tp',
      home: '/home/test',
      now: () => now,
    );

    expect(await resolver.resolveAll(), isEmpty);
    final all = await resolver.resolveAll(includeExpired: true);
    expect(all.single.userId, 'old');
    expect(all.single.providerId, 'provider-1');
    expect(
      all.single.expiresAtMs,
      lessThanOrEqualTo(now.millisecondsSinceEpoch),
    );
  });

  test(
    'includeExpired keeps the live token when both exist for one account',
    () async {
      final fs = InMemoryFilesystem();
      await fs.writeString(
        '/tp/providers/cursor/older/home/.config/cursor/auth.json',
        jsonEncode({'accessToken': _jwt(sub: 'user|a', exp: nowSeconds - 60)}),
      );
      await fs.writeString(
        '/tp/providers/cursor/newer/home/.config/cursor/auth.json',
        jsonEncode({'accessToken': _jwt(sub: 'user|a', exp: nowSeconds + 60)}),
      );

      final all = await CursorUsageAuthResolver(
        fs: fs,
        basePath: '/tp',
        home: '/home/test',
        now: () => now,
      ).resolveAll(includeExpired: true);

      expect(all.single.expiresAtMs, (nowSeconds + 60) * 1000);
    },
  );
}
