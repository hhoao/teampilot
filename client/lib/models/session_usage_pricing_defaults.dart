import 'session_usage_pricing.dart';

/// Reference list prices in USD per 1M tokens.
///
/// These are user-editable seed values, not provider-specific negotiated
/// prices. Unknown models intentionally remain unpriced.
const usageBuiltInPricingRules = <UsagePriceRule>[
  UsagePriceRule(
    model: 'claude-opus-4-1',
    inputPerMillion: 15,
    outputPerMillion: 75,
    cacheReadPerMillion: 1.5,
    cacheWritePerMillion: 18.75,
    cacheWrite1hPerMillion: 30,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-opus-4',
    inputPerMillion: 15,
    outputPerMillion: 75,
    cacheReadPerMillion: 1.5,
    cacheWritePerMillion: 18.75,
    cacheWrite1hPerMillion: 30,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-sonnet-4-5',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-sonnet-4',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-haiku-4-5',
    inputPerMillion: 1,
    outputPerMillion: 5,
    cacheReadPerMillion: 0.1,
    cacheWritePerMillion: 1.25,
    cacheWrite1hPerMillion: 2,
    source: UsagePriceSource.builtIn,
  ),
  UsagePriceRule(
    model: 'claude-3-5-sonnet',
    inputPerMillion: 3,
    outputPerMillion: 15,
    cacheReadPerMillion: 0.3,
    cacheWritePerMillion: 3.75,
    cacheWrite1hPerMillion: 6,
    source: UsagePriceSource.builtIn,
  ),
];
