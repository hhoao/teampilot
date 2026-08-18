import '../../cubits/managed_provider_cubit.dart';
import '../../cubits/managed_provider_usage_cubit.dart';
import '../../l10n/app_localizations.dart';

String managedProviderErrorMessage(
  AppLocalizations l10n, {
  ManagedProviderErrorCode? providerCode,
  ManagedProviderUsageErrorCode? usageCode,
  String? detail,
}) {
  final normalizedDetail = detail?.trim();
  if (normalizedDetail != null && normalizedDetail.isNotEmpty) {
    return normalizedDetail;
  }
  if (providerCode != null) {
    return switch (providerCode) {
      ManagedProviderErrorCode.loadFailed => l10n.managedProvidersLoadFailed,
      ManagedProviderErrorCode.saveFailed => l10n.managedProvidersSaveFailed,
      ManagedProviderErrorCode.deleteFailed =>
        l10n.managedProvidersDeleteFailed,
    };
  }
  return switch (usageCode) {
    ManagedProviderUsageErrorCode.loadFailed =>
      l10n.managedProvidersUsageLoadFailed,
    ManagedProviderUsageErrorCode.refreshFailed =>
      l10n.managedProvidersRefreshFailed,
    ManagedProviderUsageErrorCode.persistenceFailed =>
      l10n.managedProvidersUsagePersistenceFailed,
    ManagedProviderUsageErrorCode.invalidated =>
      l10n.managedProvidersUsageInvalidated,
    null => l10n.managedProvidersQueryFailed,
  };
}
