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
      ManagedProviderErrorCode.loadFailed => l10n.managedProviders.loadFailed,
      ManagedProviderErrorCode.saveFailed => l10n.managedProviders.saveFailed,
      ManagedProviderErrorCode.deleteFailed =>
        l10n.managedProviders.deleteFailed,
    };
  }
  return switch (usageCode) {
    ManagedProviderUsageErrorCode.loadFailed =>
      l10n.managedProviders.usageLoadFailed,
    ManagedProviderUsageErrorCode.refreshFailed =>
      l10n.managedProviders.refreshFailed,
    ManagedProviderUsageErrorCode.queryFailed =>
      l10n.managedProviders.queryFailed,
    ManagedProviderUsageErrorCode.persistenceFailed =>
      l10n.managedProviders.usagePersistenceFailed,
    ManagedProviderUsageErrorCode.invalidated =>
      l10n.managedProviders.usageInvalidated,
    null => l10n.managedProviders.queryFailed,
  };
}

String managedProviderSnapshotErrorMessage(
  AppLocalizations l10n,
  ProviderUsageSnapshot snapshot,
) {
  return switch (snapshot.lastErrorCode) {
    'missingCredential' => l10n.managedProviders.missingCredential,
    'authenticationFailed' => l10n.managedProviders.authenticationFailed,
    'networkFailed' => l10n.managedProviders.networkFailed,
    'httpFailed' => l10n.managedProviders.httpFailed,
    'responseParseFailed' => l10n.managedProviders.responseParseFailed,
    'unsupported' => l10n.managedProviders.queryUnsupported,
    _ =>
      snapshot.lastErrorMessage?.trim().isNotEmpty == true
          ? snapshot.lastErrorMessage!
          : l10n.managedProviders.queryFailed,
  };
}
