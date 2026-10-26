import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'team_config.dart';

/// Wire meaning of [SessionUsageEvent.inputTokens].
///
/// - [fresh]: input excludes cache (Claude, OpenCode).
/// - [total]: input includes cache read/write (Codex, Gemini, Grok).
enum UsageInputSemantics {
  fresh('fresh'),
  total('total');

  const UsageInputSemantics(this.value);

  final String value;

  static UsageInputSemantics fromJson(Object? raw) =>
      tryParse(raw?.toString()) ?? fresh;

  static UsageInputSemantics? tryParse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    for (final value in values) {
      if (value.value == normalized) return value;
    }
    return null;
  }
}

@immutable
class SessionUsageEvent extends Equatable {
  const SessionUsageEvent({
    required this.requestId,
    required this.cli,
    required this.model,
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheReadTokens,
    required this.cacheCreationTokens,
    this.cacheCreation1hTokens = 0,
    required this.inputSemantics,
    required this.timestampMs,
    required this.sessionId,
    this.memberId = '',
    this.teamId = '',
    this.isFinal = true,
    this.costMicroUsd,
  });

  /// CLI-scoped dedup key. See the design spec for the per-CLI formats.
  final String requestId;
  final CliTool cli;
  final String model;

  /// Tokens as reported by the CLI. Never rewritten.
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final int cacheCreation1hTokens;
  final UsageInputSemantics inputSemantics;

  final int timestampMs;
  final String sessionId;
  final String memberId;
  final String teamId;

  /// True when the CLI reported a settled value; false for a streaming
  /// `message_start`-style snapshot that may still grow.
  final bool isFinal;

  /// Only set when a CLI reports cost itself; no pricing table here.
  final int? costMicroUsd;

  bool get hasBillableTokens =>
      inputTokens > 0 ||
      outputTokens > 0 ||
      cacheReadTokens > 0 ||
      cacheCreationTokens > 0;

  /// Input excluding cache, for aggregation across mixed semantics.
  int get freshInputTokens {
    if (inputSemantics == UsageInputSemantics.fresh) return inputTokens;
    return (inputTokens - cacheReadTokens - cacheCreationTokens).clamp(
      0,
      inputTokens,
    );
  }

  Map<String, Object?> toJson() => {
    'requestId': requestId,
    'cli': cli.value,
    'model': model,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'cacheReadTokens': cacheReadTokens,
    'cacheCreationTokens': cacheCreationTokens,
    'cacheCreation1hTokens': cacheCreation1hTokens,
    'inputSemantics': inputSemantics.value,
    'timestampMs': timestampMs,
    'sessionId': sessionId,
    'memberId': memberId,
    'teamId': teamId,
    'isFinal': isFinal,
    if (costMicroUsd != null) 'costMicroUsd': costMicroUsd,
  };

  factory SessionUsageEvent.fromJson(Map<String, Object?> json) {
    return SessionUsageEvent(
      requestId: '${json['requestId'] ?? ''}',
      cli: CliTool.tryParse(json['cli']?.toString()) ?? CliTool.claude,
      model: '${json['model'] ?? ''}',
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadTokens: (json['cacheReadTokens'] as num?)?.toInt() ?? 0,
      cacheCreationTokens: (json['cacheCreationTokens'] as num?)?.toInt() ?? 0,
      cacheCreation1hTokens:
          (json['cacheCreation1hTokens'] as num?)?.toInt() ?? 0,
      inputSemantics: UsageInputSemantics.fromJson(json['inputSemantics']),
      timestampMs: (json['timestampMs'] as num?)?.toInt() ?? 0,
      sessionId: '${json['sessionId'] ?? ''}',
      memberId: '${json['memberId'] ?? ''}',
      teamId: '${json['teamId'] ?? ''}',
      isFinal: json['isFinal'] != false,
      costMicroUsd: (json['costMicroUsd'] as num?)?.toInt(),
    );
  }

  @override
  List<Object?> get props => [
    requestId,
    cli,
    model,
    inputTokens,
    outputTokens,
    cacheReadTokens,
    cacheCreationTokens,
    cacheCreation1hTokens,
    inputSemantics,
    timestampMs,
    sessionId,
    memberId,
    teamId,
    isFinal,
    costMicroUsd,
  ];
}
