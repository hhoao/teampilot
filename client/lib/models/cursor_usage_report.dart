import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'cursor_usage_range.dart';

@immutable
final class CursorUsageModelTotals extends Equatable {
  const CursorUsageModelTotals({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageModelTotals merge(CursorUsageModelTotals other) =>
      CursorUsageModelTotals(
        inputTokens: inputTokens + other.inputTokens,
        outputTokens: outputTokens + other.outputTokens,
        cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
        cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
        totalCents: totalCents + other.totalCents,
        chargedCents: chargedCents + other.chargedCents,
        eventCount: eventCount + other.eventCount,
      );

  Map<String, Object?> toJson() => {
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
    'eventCount': eventCount,
  };

  factory CursorUsageModelTotals.fromJson(Map<String, Object?> json) =>
      CursorUsageModelTotals(
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
        chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
        eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      );

  @override
  List<Object?> get props => [
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
  ];
}

@immutable
final class CursorUsageDay extends Equatable {
  const CursorUsageDay({
    required this.dayMs,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
    this.models = const {},
  });

  final int dayMs;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;
  final Map<String, CursorUsageModelTotals> models;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageDay merge(CursorUsageDay other) {
    final mergedModels = <String, CursorUsageModelTotals>{...models};
    for (final entry in other.models.entries) {
      mergedModels[entry.key] =
          (mergedModels[entry.key] ?? const CursorUsageModelTotals()).merge(
            entry.value,
          );
    }
    return CursorUsageDay(
      dayMs: dayMs,
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
      cacheWriteTokens: cacheWriteTokens + other.cacheWriteTokens,
      totalCents: totalCents + other.totalCents,
      chargedCents: chargedCents + other.chargedCents,
      eventCount: eventCount + other.eventCount,
      models: mergedModels,
    );
  }

  Map<String, Object?> toJson() => {
    'dayMs': dayMs,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
    'eventCount': eventCount,
    'models': {
      for (final entry in models.entries) entry.key: entry.value.toJson(),
    },
  };

  factory CursorUsageDay.fromJson(Map<String, Object?> json) {
    final rawModels = json['models'];
    final models = <String, CursorUsageModelTotals>{};
    if (rawModels is Map) {
      for (final entry in rawModels.entries) {
        final value = entry.value;
        if (value is Map) {
          models[entry.key.toString()] = CursorUsageModelTotals.fromJson(
            Map<String, Object?>.from(value),
          );
        }
      }
    }
    return CursorUsageDay(
      dayMs: (json['dayMs'] as num?)?.toInt() ?? 0,
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
      totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
      chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
      eventCount: (json['eventCount'] as num?)?.toInt() ?? 0,
      models: models,
    );
  }

  @override
  List<Object?> get props => [
    dayMs,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
    models,
  ];
}

/// One raw usage event, trimmed down to what the UI renders.
@immutable
final class CursorUsageEvent extends Equatable {
  const CursorUsageEvent({
    required this.eventId,
    required this.timestampMs,
    required this.model,
    required this.kind,
    this.owningUser = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
  });

  final String eventId;
  final int timestampMs;
  final String model;
  final String kind;

  /// Cursor's per-event account id. Used to detect a swapped session cookie.
  final String owningUser;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  CursorUsageModelTotals get totals => CursorUsageModelTotals(
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    cacheReadTokens: cacheReadTokens,
    cacheWriteTokens: cacheWriteTokens,
    totalCents: totalCents,
    chargedCents: chargedCents,
    eventCount: 1,
  );

  Map<String, Object?> toJson() => {
    'eventId': eventId,
    'timestampMs': timestampMs,
    'model': model,
    'kind': kind,
    'owningUser': owningUser,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheWriteTokens': cacheWriteTokens,
    'totalCents': totalCents,
    'chargedCents': chargedCents,
  };

  factory CursorUsageEvent.fromJson(Map<String, Object?> json) =>
      CursorUsageEvent(
        eventId: json['eventId']?.toString() ?? '',
        timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
        model: json['model']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        owningUser: json['owningUser']?.toString() ?? '',
        inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
        outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
        cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
        cacheWriteTokens: (json['cacheWriteTokens'] as num?)?.toInt() ?? 0,
        totalCents: (json['totalCents'] as num?)?.toDouble() ?? 0,
        chargedCents: (json['chargedCents'] as num?)?.toDouble() ?? 0,
      );

  @override
  List<Object?> get props => [
    eventId,
    timestampMs,
    model,
    kind,
    owningUser,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
  ];
}

/// On-disk cache for one account.
@immutable
final class CursorUsageCache extends Equatable {
  const CursorUsageCache({
    required this.accountId,
    this.owningUser,
    this.coverage = const [],
    this.days = const [],
    this.events = const [],
  });

  final String accountId;
  final String? owningUser;
  final List<CursorUsageWindow> coverage;
  final List<CursorUsageDay> days;
  final List<CursorUsageEvent> events;

  bool isCovered(int startMs, int endMs) => coverage.any(
    (window) => window.startMs <= startMs && window.endMs >= endMs,
  );

  CursorUsageCache copyWith({
    String? owningUser,
    List<CursorUsageWindow>? coverage,
    List<CursorUsageDay>? days,
    List<CursorUsageEvent>? events,
  }) => CursorUsageCache(
    accountId: accountId,
    owningUser: owningUser ?? this.owningUser,
    coverage: coverage ?? this.coverage,
    days: days ?? this.days,
    events: events ?? this.events,
  );

  Map<String, Object?> toJson() => {
    'version': 1,
    'accountId': accountId,
    'owningUser': owningUser,
    'coverage': [
      for (final window in coverage)
        {'startMs': window.startMs, 'endMs': window.endMs},
    ],
    'days': [for (final day in days) day.toJson()],
    'events': [for (final event in events) event.toJson()],
  };

  factory CursorUsageCache.fromJson(Map<String, Object?> json) {
    final rawCoverage = json['coverage'];
    final coverage = <CursorUsageWindow>[];
    if (rawCoverage is List) {
      for (final item in rawCoverage) {
        if (item is Map) {
          coverage.add(
            CursorUsageWindow(
              startMs: (item['startMs'] as num?)?.toInt() ?? 0,
              endMs: (item['endMs'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      }
    }
    final rawDays = json['days'];
    final days = <CursorUsageDay>[];
    if (rawDays is List) {
      for (final item in rawDays) {
        if (item is Map) {
          days.add(CursorUsageDay.fromJson(Map<String, Object?>.from(item)));
        }
      }
    }
    final rawEvents = json['events'];
    final events = <CursorUsageEvent>[];
    if (rawEvents is List) {
      for (final item in rawEvents) {
        if (item is Map) {
          events.add(
            CursorUsageEvent.fromJson(Map<String, Object?>.from(item)),
          );
        }
      }
    }
    return CursorUsageCache(
      accountId: json['accountId']?.toString() ?? '',
      owningUser: json['owningUser']?.toString(),
      coverage: coverage,
      days: days,
      events: events,
    );
  }

  @override
  List<Object?> get props => [accountId, owningUser, coverage, days, events];
}

/// What the page renders for one account and one range.
@immutable
final class CursorUsageReport extends Equatable {
  const CursorUsageReport({
    required this.accountId,
    required this.startMs,
    required this.endMs,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheWriteTokens = 0,
    this.totalCents = 0,
    this.chargedCents = 0,
    this.eventCount = 0,
    this.days = const [],
    this.models = const {},
    this.events = const [],
    this.summaryOnly = false,
  });

  final String accountId;
  final int startMs;
  final int endMs;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheWriteTokens;
  final double totalCents;
  final double chargedCents;
  final int eventCount;
  final List<CursorUsageDay> days;
  final Map<String, CursorUsageModelTotals> models;
  final List<CursorUsageEvent> events;

  /// True when the range reaches further back than the raw-event retention
  /// window, so [events] is empty but [days] still has the numbers.
  final bool summaryOnly;

  int get totalTokens =>
      inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens;

  @override
  List<Object?> get props => [
    accountId,
    startMs,
    endMs,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheWriteTokens,
    totalCents,
    chargedCents,
    eventCount,
    days,
    models,
    events,
    summaryOnly,
  ];
}
