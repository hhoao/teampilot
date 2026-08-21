import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/managed_provider.dart';
import 'package:teampilot/models/provider_usage_snapshot.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_usage_status_focus.dart';

ManagedProvider _p(String id) => ManagedProvider(
      id: id,
      name: id,
      kind: ManagedProviderKind.apiBalance,
      adapterId: 'fake',
      endpointConfig: ManagedProviderEndpointConfig(
        url: 'https://example.test/usage',
      ),
    );

ProviderUsageSnapshot _snap(
  String id, {
  String remaining = '10',
  int fetchedAt = 100,
  ProviderUsageStatus status = ProviderUsageStatus.ready,
}) =>
    ProviderUsageSnapshot(
      providerId: id,
      status: status,
      fetchedAt: fetchedAt,
      measures: [
        ProviderUsageMeasure(
          label: 'Balance',
          kind: ProviderUsageMeasureKind.balance,
          remaining: remaining,
          unit: 'USD',
        ),
      ],
    );

void main() {
  test('empty enabled list returns null', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: const [],
        currentSnapshots: const {},
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      isNull,
    );
  });

  test('cold start with no snapshots picks first enabled', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: const {},
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      'a',
    );
  });

  test('cold start picks max fetchedAt', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', fetchedAt: 100),
          'b': _snap('b', fetchedAt: 200),
        },
        previousSnapshots: const {},
        currentFocusId: null,
      ),
      'b',
    );
  });

  test('single changed provider becomes focus', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '9', fetchedAt: 110),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'b',
      ),
      'a',
    );
  });

  test('multiple changes pick max fetchedAt', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '1', fetchedAt: 150),
          'b': _snap('b', remaining: '2', fetchedAt: 200),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('equal fetchedAt among changes picks later enabled list order', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '1', fetchedAt: 200),
          'b': _snap('b', remaining: '2', fetchedAt: 200),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('no change keeps current focus when still enabled', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', remaining: '10', fetchedAt: 100),
          'b': _snap('b', remaining: '10', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'a',
    );
  });

  test('disabled focus falls back to cold-start rules', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('b')],
        currentSnapshots: {
          'b': _snap('b', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', fetchedAt: 50),
          'b': _snap('b', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('new snapshot absent-to-present counts as change', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', fetchedAt: 100),
          'b': _snap('b', fetchedAt: 120),
        },
        previousSnapshots: {
          'a': _snap('a', fetchedAt: 100),
        },
        currentFocusId: 'a',
      ),
      'b',
    );
  });

  test('status change counts as change', () {
    expect(
      resolveManagedProviderUsageFocus(
        enabledProviders: [_p('a'), _p('b')],
        currentSnapshots: {
          'a': _snap('a', status: ProviderUsageStatus.stale, fetchedAt: 110),
          'b': _snap('b', fetchedAt: 100),
        },
        previousSnapshots: {
          'a': _snap('a', status: ProviderUsageStatus.ready, fetchedAt: 100),
          'b': _snap('b', fetchedAt: 100),
        },
        currentFocusId: 'b',
      ),
      'a',
    );
  });
}
