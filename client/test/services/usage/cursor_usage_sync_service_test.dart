import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/services/cli/cursor/provider/cursor_usage_auth_resolver.dart';
import 'package:teampilot/services/usage/cursor_usage_import_store.dart';
import 'package:teampilot/services/usage/cursor_usage_sync_service.dart';

import '../../support/in_memory_filesystem.dart';

String _jwt({required String sub, required int exp}) {
  String enc(Map<String, Object?> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${enc({'alg': 'none'})}.${enc({'sub': sub, 'exp': exp})}.sig';
}

const _csv =
    'Date,Cloud Agent ID,Automation ID,Kind,Model,Max Mode,'
    'Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,'
    'Output Tokens,Total Tokens,Cost\n'
    '2026-10-26T10:00:00Z,,,chat,claude-sonnet-4,,0,100,10,20,130,\$0.50\n';

void main() {
  final now = DateTime.utc(2026, 10, 28, 12);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  test('syncs the dashboard CSV with the app cookie', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/home/test/.config/cursor/auth.json',
      jsonEncode({'accessToken': _jwt(sub: 'user|u1', exp: nowSeconds + 3600)}),
    );
    final store = CursorUsageImportStore(
      fs: fs,
      filePath: '/tp/usage/cursor_import.json',
    );
    final requests = <http.Request>[];
    final service = CursorUsageSyncService(
      store: store,
      auth: CursorUsageAuthResolver(
        fs: fs,
        basePath: '/tp',
        home: '/home/test',
        now: () => now,
      ),
      now: () => now,
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(_csv, 200);
      }),
    );

    final result = await service.sync();

    expect(result.inserted, 1);
    expect(result.status.eventCount, 1);
    expect(requests, hasLength(1));
    expect(requests.single.url.queryParameters['strategy'], 'tokens');
    expect(
      requests.single.headers['Cookie'],
      startsWith('WorkosCursorSessionToken=u1%3A%3A'),
    );
    final events = await service.loadEvents();
    expect(events.single.outputTokens, 20);
    expect(events.single.costMicroUsd, 500000);
  });

  test('maps 401 to a login error', () async {
    final fs = InMemoryFilesystem();
    await fs.writeString(
      '/home/test/.config/cursor/auth.json',
      jsonEncode({'accessToken': _jwt(sub: 'user|u1', exp: nowSeconds + 3600)}),
    );
    final service = CursorUsageSyncService(
      store: CursorUsageImportStore(
        fs: fs,
        filePath: '/tp/usage/cursor_import.json',
      ),
      auth: CursorUsageAuthResolver(
        fs: fs,
        basePath: '/tp',
        home: '/home/test',
        now: () => now,
      ),
      now: () => now,
      httpClient: MockClient((request) async => http.Response('no', 401)),
    );

    await expectLater(
      service.sync(),
      throwsA(
        isA<CursorUsageSyncException>().having(
          (e) => e.code,
          'code',
          CursorUsageSyncError.login,
        ),
      ),
    );
  });
}
