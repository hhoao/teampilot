import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_api_client.dart';

const _credentials = CursorAccountCredentials(
  accountId: 'abc',
  userId: 'user_01ABC',
  token: 'eyJ.payload.sig',
  expiresAtMs: 2000000000000,
);

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('parses events and passes the session cookie and body', () async {
    late http.Request captured;
    final client = CursorUsageApiClient(
      client: MockClient((request) async {
        captured = request;
        return _json({
          'totalUsageEventsCount': 1,
          'usageEventsDisplay': [
            {
              'timestamp': '1793106557868',
              'model': 'cursor-grok-4.6-high',
              'kind': 'USAGE_EVENT_KIND_INCLUDED_IN_PRO',
              'tokenUsage': {
                'inputTokens': 9598,
                'outputTokens': 4642,
                'cacheReadTokens': 335488,
                'cacheWriteTokens': 7,
                'totalCents': 21.5,
              },
              'owningUser': '380653899',
              'chargedCents': 0.0,
              'usageEventId': 'evt-1',
            },
          ],
        });
      }),
    );

    final page = await client.fetchPage(
      credentials: _credentials,
      startMs: 1000,
      endMs: 2000,
      page: 2,
    );

    expect(captured.headers['Cookie'], _credentials.cookie);
    expect(captured.headers['Origin'], 'https://cursor.com');
    final body = jsonDecode(captured.body) as Map<String, Object?>;
    expect(body['teamId'], 0);
    expect(body['startDate'], '1000');
    expect(body['endDate'], '2000');
    expect(body['page'], 2);
    expect(body['pageSize'], 500);

    expect(page.totalCount, 1);
    final event = page.events.single;
    expect(event.eventId, 'evt-1');
    expect(event.timestampMs, 1793106557868);
    expect(event.cacheWriteTokens, 7);
    expect(event.totalCents, 21.5);
  });

  test('maps 401 to login', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {}, status: 401)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.login,
        ),
      ),
    );
  });

  test('maps 429 to rateLimited', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {}, status: 429)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.rateLimited,
        ),
      ),
    );
  });

  test('a non-json body is invalidResponse', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => http.Response('not json at all', 200)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.invalidResponse,
        ),
      ),
    );
  });

  test('an html body is treated as a login page', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => http.Response('<html></html>', 200)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.login,
        ),
      ),
    );
  });

  test('an empty body is invalidResponse', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => http.Response('', 200)),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.invalidResponse,
        ),
      ),
    );
  });

  test('a zero total without an events array is an empty page', () async {
    final client = CursorUsageApiClient(
      client: MockClient(
        (_) async => _json(const {'totalUsageEventsCount': 0}),
      ),
    );
    final page = await client.fetchPage(
      credentials: _credentials,
      startMs: 0,
      endMs: 1,
      page: 1,
    );
    expect(page.events, isEmpty);
    expect(page.totalCount, 0);
  });

  test('an empty json object is an empty page, not an error', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const <String, Object?>{})),
    );
    final page = await client.fetchPage(
      credentials: _credentials,
      startMs: 0,
      endMs: 1,
      page: 1,
    );
    expect(page.events, isEmpty);
    expect(page.totalCount, 0);
  });

  test('a 200 error envelope without events is invalidResponse', () async {
    final client = CursorUsageApiClient(
      client: MockClient(
        (_) async => _json(const {'error': 'nope', 'totalUsageEventsCount': 5}),
      ),
    );
    await expectLater(
      client.fetchPage(
        credentials: _credentials,
        startMs: 0,
        endMs: 1,
        page: 1,
      ),
      throwsA(
        isA<CursorUsageApiException>().having(
          (error) => error.code,
          'code',
          CursorUsageApiError.invalidResponse,
        ),
      ),
    );
  });

  test('fetchBillingCycle parses the ISO bounds', () async {
    final client = CursorUsageApiClient(
      client: MockClient(
        (_) async => _json({
          'billingCycleStart': '2026-10-06T07:05:16.000Z',
          'billingCycleEnd': '2026-11-06T07:05:16.000Z',
        }),
      ),
    );
    final cycle = await client.fetchBillingCycle(credentials: _credentials);
    expect(cycle, isNotNull);
    expect(
      cycle!.startMs,
      DateTime.utc(2026, 10, 6, 7, 5, 16).millisecondsSinceEpoch,
    );
    expect(
      cycle.endMs,
      DateTime.utc(2026, 11, 6, 7, 5, 16).millisecondsSinceEpoch,
    );
  });

  test('fetchBillingCycle sends the session cookie', () async {
    late http.Request captured;
    final client = CursorUsageApiClient(
      client: MockClient((request) async {
        captured = request;
        return _json(const {'membershipType': 'pro'});
      }),
    );
    await client.fetchBillingCycle(credentials: _credentials);
    expect(captured.headers['Cookie'], _credentials.cookie);
  });

  test('fetchBillingCycle returns null when the fields are absent', () async {
    final client = CursorUsageApiClient(
      client: MockClient((_) async => _json(const {'membershipType': 'pro'})),
    );
    expect(await client.fetchBillingCycle(credentials: _credentials), isNull);
  });
}
