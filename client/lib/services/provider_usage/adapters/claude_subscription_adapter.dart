import 'official_subscription_adapter.dart';

/// Official Claude subscription usage adapter.
class ClaudeSubscriptionAdapter extends OfficialSubscriptionAdapter {
  static const stableAdapterId = 'official-claude-subscription';
  static const stableProviderId = 'claude';

  const ClaudeSubscriptionAdapter({
    required super.authReader,
    required super.client,
  });

  @override
  String get id => stableAdapterId;

  @override
  String get officialProviderId => stableProviderId;
}
