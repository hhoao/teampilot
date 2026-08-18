import 'official_subscription_adapter.dart';

/// Official Codex subscription usage adapter.
class CodexSubscriptionAdapter extends OfficialSubscriptionAdapter {
  static const stableAdapterId = 'official-codex-subscription';
  static const stableProviderId = 'codex';

  const CodexSubscriptionAdapter({
    required super.authReader,
    required super.client,
  });

  @override
  String get id => stableAdapterId;

  @override
  String get officialProviderId => stableProviderId;
}
