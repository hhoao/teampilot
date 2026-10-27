import '../../models/session_usage_pricing.dart';

final class UsagePricingLoad {
  const UsagePricingLoad({required this.rules, this.corrupted = false});

  final List<UsagePriceRule> rules;
  final bool corrupted;
}

abstract interface class UsagePricingStore {
  Future<UsagePricingLoad> load();

  Future<void> save(List<UsagePriceRule> rules);
}
