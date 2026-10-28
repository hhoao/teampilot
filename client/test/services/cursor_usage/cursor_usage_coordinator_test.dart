import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cursor_usage_account.dart';
import 'package:teampilot/models/cursor_usage_range.dart';
import 'package:teampilot/models/cursor_usage_report.dart';
import 'package:teampilot/services/cursor_usage/cursor_account_registry.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_api_client.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_cache_store.dart';
import 'package:teampilot/services/cursor_usage/cursor_usage_coordinator.dart';

import '../../support/in_memory_filesystem.dart';

int ms(int day) => DateTime(2026, 10, day).millisecondsSinceEpoch;

CursorUsageEvent event(String id, int day, {String owner = '111'}) =>
    CursorUsageEvent(
      eventId: id,
      timestampMs: ms(day) + 1000,
      model: 'cursor-grok-4.6-high',
      kind: 'USAGE_EVENT_KIND_INCLUDED_IN_PRO',
      owningUser: owner,
      inputTokens: 10,
      totalCents: 1,
    );

CursorUsageAccount accountRow({String? owningUser, int teamId = 0}) =>
    CursorUsageAccount(
      accountId: 'acct',
      userId: 'user_01ABC',
      label: 'Cursor · acct',
      source: CursorAccountSource.manual,
      owningUser: owningUser,
      teamId: teamId,
    );

class _FakeApi implements CursorUsageApi {
  _FakeApi({this.pages = const []});

  final List<CursorUsagePage> pages;
  final calls = <(int, int, int)>[];
  Object? throwOnFetch;

  @override
  Future<CursorUsagePage> fetchPage({
    required CursorAccountCredentials credentials,
    required int startMs,
    required int endMs,
    required int page,
    int pageSize = 500,
    int teamId = 0,
  }) async {
    calls.add((startMs, endMs, page));
    final error = throwOnFetch;
    if (error != null) throw error;
    final index = page - 1;
    if (index >= pages.length) {
      return const CursorUsagePage(events: [], totalCount: 0);
    }
    return pages[index];
  }

  @override
  Future<CursorUsageWindow?> fetchBillingCycle({
    required CursorAccountCredentials credentials,
  }) async => null;
}

class _FakeRegistry implements CursorAccountDirectory {
  _FakeRegistry(this.credential, {this.owningUser, this.accounts = const []});

  final CursorAccountCredentials? credential;
  final List<CursorUsageAccount> accounts;
  String? owningUser;
  int bindCalls = 0;

  @override
  Future<CursorAccountCredentials?> credentialFor(String accountId) async =>
      credential;

  @override
  Future<void> update(
    String accountId, {
    String? label,
    bool? enabled,
    int? teamId,
    String? owningUser,
  }) async {
    bindCalls++;
    this.owningUser = owningUser ?? this.owningUser;
  }

  @override
  Future<List<CursorUsageAccount>> list() async => accounts;

  @override
  Future<void> upsertManual(
    CursorAccountCredentials credentials, {
    String? label,
    int? teamId,
  }) async {}

  @override
  Future<void> remove(String accountId) async {}
}

const _credentials = CursorAccountCredentials(
  accountId: 'acct',
  userId: 'user_01ABC',
  token: 'tok',
  expiresAtMs: 2000000000000,
);

void main() {
  late InMemoryFilesystem fs;
  late CursorUsageCacheStore cacheStore;

  setUp(() {
    fs = InMemoryFilesystem();
    cacheStore = CursorUsageCacheStore(
      fs: fs,
      pathFor: (accountId) => '/root/cursor_usage/cache/$accountId.json',
    );
  });

  CursorUsageCoordinator coordinator({
    required CursorUsageApi api,
    required _FakeRegistry registry,
  }) => CursorUsageCoordinator(
    registry: registry,
    cacheStore: cacheStore,
    api: api,
    now: () => DateTime.fromMillisecondsSinceEpoch(ms(28) + 3600000),
  );

  test('fetches every page until the total is reached', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 2),
        CursorUsagePage(events: [event('e2', 28)], totalCount: 2),
      ],
    );
    final report =
        await coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
          accountId: 'acct',
          range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
        );

    expect(api.calls.length, 2);
    expect(api.calls[1].$3, 2);
    expect(report.eventCount, 2);
  });

  test('a second load inside the covered range makes no request', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 1),
      ],
    );
    final coord = coordinator(api: api, registry: _FakeRegistry(_credentials));
    final range = CursorUsageCustomRange(startMs: ms(28), endMs: ms(28));
    await coord.load(accountId: 'acct', range: range);
    await coord.load(accountId: 'acct', range: range);
    expect(api.calls.length, 1);
  });

  test('forceRefresh refetches a range the cache already covers', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 1),
      ],
    );
    final coord = coordinator(api: api, registry: _FakeRegistry(_credentials));
    final range = CursorUsageCustomRange(startMs: ms(28), endMs: ms(28));
    await coord.load(accountId: 'acct', range: range);
    await coord.load(accountId: 'acct', range: range, forceRefresh: true);
    expect(api.calls.length, 2);
  });

  test('stops at the page cap and reports rangeTooLarge', () async {
    final api = _FakeApi(
      pages: [
        for (var i = 0; i < 40; i++)
          CursorUsagePage(events: [event('e$i', 28)], totalCount: 99999),
      ],
    );
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(1), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.rangeTooLarge,
        ),
      ),
    );
    expect(api.calls.length, 40);
  });

  test('a truncated page is not cached as covered', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 5),
      ],
    );
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.invalidResponse,
        ),
      ),
    );
    expect(fs.files, isEmpty);
  });

  test('binds owningUser on first fetch and rejects a later swap', () async {
    final registry = _FakeRegistry(_credentials, owningUser: '111');
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28)], totalCount: 1),
      ],
    );
    final coord = coordinator(api: api, registry: registry);
    await coord.load(
      accountId: 'acct',
      range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
    );
    expect(registry.bindCalls, 1);
    expect(registry.owningUser, '111');

    final swapped = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e2', 27, owner: '222')], totalCount: 1),
      ],
    );
    await expectLater(
      coordinator(api: swapped, registry: registry).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(27), endMs: ms(27)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.accountMismatch,
        ),
      ),
    );
  });

  test('consults the durable owningUser when the cache is empty', () async {
    final registry = _FakeRegistry(
      _credentials,
      accounts: [accountRow(owningUser: '111')],
    );
    final api = _FakeApi(
      pages: [
        CursorUsagePage(events: [event('e1', 28, owner: '222')], totalCount: 1),
      ],
    );
    await expectLater(
      coordinator(api: api, registry: registry).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.accountMismatch,
        ),
      ),
    );
    expect(fs.files, isEmpty);
  });

  test(
    'a later gap with the same owner does not rewrite the account',
    () async {
      final registry = _FakeRegistry(_credentials);
      final api = _FakeApi(
        pages: [
          CursorUsagePage(events: [event('e1', 27)], totalCount: 1),
          CursorUsagePage(events: [event('e2', 28)], totalCount: 1),
        ],
      );
      final coord = coordinator(api: api, registry: registry);
      await coord.load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(27), endMs: ms(27)),
      );
      await coord.load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      );
      expect(registry.bindCalls, 1);
    },
  );

  test('team accounts skip the owningUser check', () async {
    final registry = _FakeRegistry(
      _credentials,
      accounts: [accountRow(teamId: 4)],
    );
    final api = _FakeApi(
      pages: [
        CursorUsagePage(
          events: [
            event('e1', 28),
            event('e2', 28, owner: '222'),
          ],
          totalCount: 2,
        ),
      ],
    );
    final report = await coordinator(api: api, registry: registry).load(
      accountId: 'acct',
      range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
    );
    expect(report.eventCount, 2);
  });

  test('matches events for more than one user are rejected', () async {
    final api = _FakeApi(
      pages: [
        CursorUsagePage(
          events: [
            event('e1', 28),
            event('e2', 28, owner: '222'),
          ],
          totalCount: 2,
        ),
      ],
    );
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.accountMismatch,
        ),
      ),
    );
  });

  test('missing credential fails before any request', () async {
    final api = _FakeApi();
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(null)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.noCredential,
        ),
      ),
    );
    expect(api.calls, isEmpty);
  });

  test('maps an api failure and leaves the cache untouched', () async {
    final api = _FakeApi()
      ..throwOnFetch = const CursorUsageApiException(
        CursorUsageApiError.rateLimited,
        'slow down',
      );
    await expectLater(
      coordinator(api: api, registry: _FakeRegistry(_credentials)).load(
        accountId: 'acct',
        range: CursorUsageCustomRange(startMs: ms(28), endMs: ms(28)),
      ),
      throwsA(
        isA<CursorUsageException>().having(
          (error) => error.failure,
          'failure',
          CursorUsageFailure.rateLimited,
        ),
      ),
    );
    expect(fs.files, isEmpty);
  });
}
