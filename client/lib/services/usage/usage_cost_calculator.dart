import '../../models/session_usage.dart';
import '../../models/session_usage_pricing.dart';

UsageCost calculateUsageCost(
  SessionUsageEvent event,
  UsagePricingCatalog catalog,
) {
  final reported = event.costMicroUsd;
  if (reported != null) {
    return UsageCost(microUsd: reported, kind: UsageCostKind.reported);
  }

  final rule = catalog.ruleFor(
    model: event.model,
    timestampMs: event.timestampMs,
  );
  if (rule == null) {
    return const UsageCost(microUsd: null, kind: UsageCostKind.unpriced);
  }

  final oneHour = event.cacheCreation1hTokens.clamp(
    0,
    event.cacheCreationTokens,
  );
  final regularWrite = event.cacheCreationTokens - oneHour;
  final write1hRate = rule.cacheWrite1hPerMillion ?? rule.cacheWritePerMillion;
  final microUsd =
      (event.freshInputTokens * rule.inputPerMillion +
              event.outputTokens * rule.outputPerMillion +
              event.cacheReadTokens * rule.cacheReadPerMillion +
              regularWrite * rule.cacheWritePerMillion +
              oneHour * write1hRate)
          .round();

  return UsageCost(microUsd: microUsd, kind: UsageCostKind.priced);
}
