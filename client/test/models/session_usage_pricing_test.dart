import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_usage_pricing.dart';

UsagePriceRule _rule({
  required String model,
  double input = 1,
  double output = 2,
  double cacheRead = 0.1,
  double cacheWrite = 1.25,
  double? cacheWrite1h,
  int effectiveFromMs = 0,
  UsagePriceSource source = UsagePriceSource.user,
}) => UsagePriceRule(
  model: model,
  inputPerMillion: input,
  outputPerMillion: output,
  cacheReadPerMillion: cacheRead,
  cacheWritePerMillion: cacheWrite,
  cacheWrite1hPerMillion: cacheWrite1h,
  effectiveFromMs: effectiveFromMs,
  source: source,
);

void main() {
  test('normalizes case and date suffixes', () {
    expect(
      usageNormalizeModelId(' Claude-Sonnet-4-5-20250929 '),
      'claude-sonnet-4-5',
    );
    expect(usageNormalizeModelId('gpt-5.4'), 'gpt-5.4');
    expect(
      usageNormalizeModelId('claude-3-5-sonnet-2024-10-22'),
      'claude-3-5-sonnet',
    );
  });

  test('picks the latest rule not after the event timestamp', () {
    final catalog = UsagePricingCatalog(
      builtInRules: const [],
      userRules: [
        _rule(model: 'm', input: 1, effectiveFromMs: 100),
        _rule(model: 'm', input: 2, effectiveFromMs: 200),
      ],
    );

    expect(catalog.ruleFor(model: 'm', timestampMs: 99), isNull);
    expect(catalog.ruleFor(model: 'm', timestampMs: 150)?.inputPerMillion, 1);
    expect(catalog.ruleFor(model: 'm', timestampMs: 250)?.inputPerMillion, 2);
  });

  test('user rule wins at the same effective time', () {
    final catalog = UsagePricingCatalog(
      builtInRules: [
        _rule(model: 'm', input: 1, source: UsagePriceSource.builtIn),
      ],
      userRules: [_rule(model: 'm', input: 9)],
    );

    expect(catalog.ruleFor(model: 'm', timestampMs: 0)?.inputPerMillion, 9);
  });
}
