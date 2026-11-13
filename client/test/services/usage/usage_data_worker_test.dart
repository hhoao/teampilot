import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/usage_data_worker.dart';

SessionUsageEvent _event({
  required String id,
  int output = 1,
  int timestampMs = 100,
  CliTool cli = CliTool.claude,
}) {
  return SessionUsageEvent(
    requestId: id,
    cli: cli,
    model: 'm',
    inputTokens: 10,
    outputTokens: output,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    inputSemantics: UsageInputSemantics.fresh,
    timestampMs: timestampMs,
    sessionId: 's1',
  );
}

Uint8List _jsonl(List<SessionUsageEvent> events, {int revision = 0}) =>
    Uint8List.fromList(
      utf8.encode(
        [
          for (final event in events)
            jsonEncode({'rev': revision, 'event': event.toJson()}),
        ].join('\n'),
      ),
    );

UsageLoad _load(
  UsageSource source, {
  UsageFilter filter = const UsageFilter(),
  int nowMs = 1000,
}) {
  return UsageLoad(
    source: source,
    attribution: const UsageAttribution(),
    pricing: const UsagePricingCatalog(),
    filter: filter,
    nowMs: nowMs,
  );
}

void main() {
  group('decodeUsageEvents', () {
    test('higher revision replaces a duplicate request id', () {
      final older = _event(id: 'a', output: 1);
      final newer = _event(id: 'a', output: 9);
      final source = UsageSource(
        eventsJsonl: Uint8List.fromList(
          '${jsonEncode({'rev': 0, 'event': older.toJson()})}\n'
                  '${jsonEncode({'rev': 2, 'event': newer.toJson()})}\n'
              .codeUnits,
        ),
      );

      final events = decodeUsageEvents(source);

      expect(events, hasLength(1));
      expect(events.single.outputTokens, 9);
    });

    test('cursor events override base and the result is time-sorted', () {
      final base = _event(id: 'a', output: 1, timestampMs: 300);
      final other = _event(id: 'b', output: 2, timestampMs: 200);
      final cursor = _event(
        id: 'a',
        output: 7,
        timestampMs: 100,
        cli: CliTool.cursor,
      );
      final source = UsageSource(
        eventsJsonl: _jsonl([base, other]),
        cursorEvents: [cursor],
      );

      final events = decodeUsageEvents(source);

      expect(events.map((e) => e.requestId), ['a', 'b']);
      expect(events.first.outputTokens, 7);
      expect(events.first.cli, CliTool.cursor);
    });

    test('malformed and blank lines are skipped', () {
      final good = _event(id: 'a');
      final source = UsageSource(
        eventsJsonl: Uint8List.fromList(
          '\nnot json\n'
                  '${jsonEncode({'rev': 0, 'event': good.toJson()})}\n'
                  '{"rev":0}\n'
              .codeUnits,
        ),
      );

      final events = decodeUsageEvents(source);

      expect(events.map((e) => e.requestId), ['a']);
    });

    test('UsageSource.fromEvents round-trips through the decoder', () {
      final events = [
        _event(id: 'a', timestampMs: 200),
        _event(id: 'b', timestampMs: 100),
      ];

      final decoded = decodeUsageEvents(UsageSource.fromEvents(events));

      expect(decoded.map((e) => e.requestId), ['b', 'a']);
      expect(decoded.first.outputTokens, events.last.outputTokens);
    });
  });

  group('IsolateUsageDataWorker', () {
    test('load and compute run in a resident isolate', () async {
      final worker = IsolateUsageDataWorker();
      addTearDown(worker.close);
      final source = UsageSource.fromEvents([
        _event(id: 'a', output: 1, cli: CliTool.claude),
        _event(id: 'b', output: 2, cli: CliTool.codex),
      ]);

      final initial = await worker.load(_load(source));
      expect(initial.summary.requests, 2);

      final filtered = await worker.compute(
        const UsageFilter(cli: CliTool.codex),
        1000,
      );

      expect(filtered.summary.requests, 1);
      expect(filtered.summary.totalTokens, 12);
    });
  });

  group('InlineUsageDataWorker', () {
    test('load builds a dashboard and compute reuses the loaded events', () async {
      final worker = InlineUsageDataWorker();
      addTearDown(worker.close);
      final source = UsageSource.fromEvents([
        _event(id: 'a', output: 1, cli: CliTool.claude),
        _event(id: 'b', output: 2, cli: CliTool.codex),
      ]);

      final initial = await worker.load(_load(source));
      expect(initial.summary.requests, 2);

      final filtered = await worker.compute(
        const UsageFilter(cli: CliTool.codex),
        1000,
      );

      expect(filtered.summary.requests, 1);
      expect(filtered.summary.totalTokens, 12);
    });

    test('compute with new pricing reprices without a reload', () async {
      final worker = InlineUsageDataWorker();
      addTearDown(worker.close);
      final source = UsageSource.fromEvents([_event(id: 'a', output: 0)]);
      final pricing = UsagePricingCatalog(
        userRules: const [
          UsagePriceRule(
            model: 'm',
            inputPerMillion: 1,
            outputPerMillion: 0,
          ),
        ],
      );

      final before = await worker.load(_load(source));
      final after = await worker.compute(
        const UsageFilter(),
        1000,
        pricing: pricing,
      );

      expect(before.summary.pricedEvents, 0);
      expect(after.summary.pricedEvents, 1);
      expect(after.summary.costMicroUsd, greaterThan(0));
    });
  });
}
