import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import 'session_usage_pricing_defaults.dart';

enum UsagePriceSource { builtIn, user }

enum UsageCostKind { reported, priced, unpriced }

String usageNormalizeModelId(String raw) {
  var value = raw.trim().toLowerCase();
  value = value.replaceFirst(RegExp(r'-\d{4}-\d{2}-\d{2}$'), '');
  value = value.replaceFirst(RegExp(r'-\d{8}$'), '');
  return value.trim();
}

@immutable
final class UsagePriceRule extends Equatable {
  const UsagePriceRule({
    required this.model,
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.cacheReadPerMillion = 0,
    this.cacheWritePerMillion = 0,
    this.cacheWrite1hPerMillion,
    this.effectiveFromMs = 0,
    this.source = UsagePriceSource.user,
  });

  final String model;
  final double inputPerMillion;
  final double outputPerMillion;
  final double cacheReadPerMillion;
  final double cacheWritePerMillion;
  final double? cacheWrite1hPerMillion;
  final int effectiveFromMs;
  final UsagePriceSource source;

  String get normalizedModel => usageNormalizeModelId(model);

  UsagePriceRule copyWith({
    String? model,
    double? inputPerMillion,
    double? outputPerMillion,
    double? cacheReadPerMillion,
    double? cacheWritePerMillion,
    double? cacheWrite1hPerMillion,
    bool clearCacheWrite1h = false,
    int? effectiveFromMs,
    UsagePriceSource? source,
  }) {
    return UsagePriceRule(
      model: model ?? this.model,
      inputPerMillion: inputPerMillion ?? this.inputPerMillion,
      outputPerMillion: outputPerMillion ?? this.outputPerMillion,
      cacheReadPerMillion: cacheReadPerMillion ?? this.cacheReadPerMillion,
      cacheWritePerMillion: cacheWritePerMillion ?? this.cacheWritePerMillion,
      cacheWrite1hPerMillion: clearCacheWrite1h
          ? null
          : (cacheWrite1hPerMillion ?? this.cacheWrite1hPerMillion),
      effectiveFromMs: effectiveFromMs ?? this.effectiveFromMs,
      source: source ?? this.source,
    );
  }

  Map<String, Object?> toJson() => {
    'model': model,
    'inputPerMillion': inputPerMillion,
    'outputPerMillion': outputPerMillion,
    'cacheReadPerMillion': cacheReadPerMillion,
    'cacheWritePerMillion': cacheWritePerMillion,
    if (cacheWrite1hPerMillion != null)
      'cacheWrite1hPerMillion': cacheWrite1hPerMillion,
    'effectiveFromMs': effectiveFromMs,
  };

  factory UsagePriceRule.fromJson(Map<String, Object?> json) {
    return UsagePriceRule(
      model: '${json['model'] ?? ''}',
      inputPerMillion: (json['inputPerMillion'] as num?)?.toDouble() ?? 0,
      outputPerMillion: (json['outputPerMillion'] as num?)?.toDouble() ?? 0,
      cacheReadPerMillion:
          (json['cacheReadPerMillion'] as num?)?.toDouble() ?? 0,
      cacheWritePerMillion:
          (json['cacheWritePerMillion'] as num?)?.toDouble() ?? 0,
      cacheWrite1hPerMillion: (json['cacheWrite1hPerMillion'] as num?)
          ?.toDouble(),
      effectiveFromMs: (json['effectiveFromMs'] as num?)?.toInt() ?? 0,
      source: UsagePriceSource.user,
    );
  }

  @override
  List<Object?> get props => [
    model,
    inputPerMillion,
    outputPerMillion,
    cacheReadPerMillion,
    cacheWritePerMillion,
    cacheWrite1hPerMillion,
    effectiveFromMs,
    source,
  ];
}

@immutable
final class UsageCost extends Equatable {
  const UsageCost({required this.microUsd, required this.kind});

  final int? microUsd;
  final UsageCostKind kind;

  @override
  List<Object?> get props => [microUsd, kind];
}

@immutable
final class UsagePricingCatalog extends Equatable {
  const UsagePricingCatalog({
    this.builtInRules = const [],
    this.userRules = const [],
  });

  factory UsagePricingCatalog.builtIn() =>
      const UsagePricingCatalog(builtInRules: usageBuiltInPricingRules);

  final List<UsagePriceRule> builtInRules;
  final List<UsagePriceRule> userRules;

  UsagePriceRule? ruleFor({required String model, required int timestampMs}) {
    final key = usageNormalizeModelId(model);
    if (key.isEmpty) return null;

    UsagePriceRule? best;
    for (final rule in [...userRules, ...builtInRules]) {
      if (rule.normalizedModel != key) continue;
      if (rule.effectiveFromMs > timestampMs) continue;
      if (best == null ||
          rule.effectiveFromMs > best.effectiveFromMs ||
          (rule.effectiveFromMs == best.effectiveFromMs &&
              rule.source == UsagePriceSource.user)) {
        best = rule;
      }
    }
    return best;
  }

  @override
  List<Object?> get props => [builtInRules, userRules];
}
