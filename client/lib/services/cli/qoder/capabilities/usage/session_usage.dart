import '../../../registry/capabilities/session_usage_capability.dart';

/// Usage parsing lands in Task 6; registered now so the registry shape is
/// stable.
final class QoderSessionUsageCapability implements SessionUsageCapability {
  const QoderSessionUsageCapability();

  @override
  Future<List<SessionUsageSource>> discoverUsageSources(
    UsageScanContext ctx,
  ) async => const [];

  @override
  Future<UsageScanResult> scanUsageSource({
    required UsageScanContext ctx,
    required SessionUsageSource source,
    required UsageCursor? cursor,
  }) async => const UsageScanResult(events: [], nextCursor: UsageCursor.empty);
}
