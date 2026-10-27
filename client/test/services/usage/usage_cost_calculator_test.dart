import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage.dart';
import 'package:teampilot/models/session_usage_pricing.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/usage/usage_cost_calculator.dart';

SessionUsageEvent _event({
  String model = 'm',
  int input = 1000000,
  int output = 1000000,
  int cacheRead = 0,
  int cacheCreate = 0,
  int cacheCreate1h = 0,
  UsageInputSemantics semantics = UsageInputSemantics.fresh,
  int? reported,
}) => SessionUsageEvent(
  requestId: 'r',
  cli: CliTool.claude,
  model: model,
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: cacheRead,
  cacheCreationTokens: cacheCreate,
  cacheCreation1hTokens: cacheCreate1h,
  inputSemantics: semantics,
  timestampMs: 100,
  sessionId: 's',
  costMicroUsd: reported,
);

final _catalog = UsagePricingCatalog(
  builtInRules: const [],
  userRules: [
    UsagePriceRule(
      model: 'm',
      inputPerMillion: 3,
      outputPerMillion: 15,
      cacheReadPerMillion: 0.3,
      cacheWritePerMillion: 3.75,
      cacheWrite1hPerMillion: 6,
      effectiveFromMs: 0,
      source: UsagePriceSource.user,
    ),
  ],
);

void main() {
  test('calculates fresh input, output, cache read and write', () {
    final cost = calculateUsageCost(
      _event(
        input: 1000000,
        output: 2000000,
        cacheRead: 500000,
        cacheCreate: 200000,
        cacheCreate1h: 100000,
      ),
      _catalog,
    );

    expect(cost.kind, UsageCostKind.priced);
    expect(cost.microUsd, 3000000 + 30000000 + 150000 + 375000 + 600000);
  });

  test('normalizes total input semantics', () {
    final cost = calculateUsageCost(
      _event(
        input: 1000000,
        output: 0,
        cacheRead: 400000,
        semantics: UsageInputSemantics.total,
      ),
      _catalog,
    );

    expect(cost.microUsd, 600000 * 3 + 400000 * 0.3);
  });

  test('reported cost wins', () {
    final cost = calculateUsageCost(_event(reported: 1234), _catalog);
    expect(cost.kind, UsageCostKind.reported);
    expect(cost.microUsd, 1234);
  });

  test('unknown model is unpriced', () {
    final cost = calculateUsageCost(_event(model: 'unknown'), _catalog);
    expect(cost.kind, UsageCostKind.unpriced);
    expect(cost.microUsd, isNull);
  });
}
