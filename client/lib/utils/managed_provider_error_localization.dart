import '../cubits/managed_provider_cubit.dart';
import '../cubits/managed_provider_usage_cubit.dart';
import '../l10n/app_localizations.dart';
import '../models/provider_usage_snapshot.dart';

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
    ManagedProviderUsageErrorCode.queryFailed =>
      l10n.managedProvidersQueryFailed,
    ManagedProviderUsageErrorCode.persistenceFailed =>
      l10n.managedProvidersUsagePersistenceFailed,
    ManagedProviderUsageErrorCode.invalidated =>
      l10n.managedProvidersUsageInvalidated,
    null => l10n.managedProvidersQueryFailed,
  };
}

String managedProviderSnapshotErrorMessage(
  AppLocalizations l10n,
  ProviderUsageSnapshot snapshot,
) {
  return switch (snapshot.lastErrorCode) {
    'missingCredential' => l10n.managedProvidersMissingCredential,
    'authenticationFailed' => l10n.managedProvidersAuthenticationFailed,
    'networkFailed' => l10n.managedProvidersNetworkFailed,
    'httpFailed' => l10n.managedProvidersHttpFailed,
    'responseParseFailed' => l10n.managedProvidersResponseParseFailed,
    'unsupported' => l10n.managedProvidersQueryUnsupported,
    _ =>
      snapshot.lastErrorMessage?.trim().isNotEmpty == true
          ? snapshot.lastErrorMessage!
          : l10n.managedProvidersQueryFailed,
  };
}
