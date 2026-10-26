import '../cli/registry/capabilities/session_usage_capability.dart';

/// Narrow seam so the sync service can be tested without repositories.
abstract interface class UsageScanTargetProvider {
  Future<List<UsageScanContext>> targets();
}
