import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../managed_provider_usage_adapter.dart';

/// Reads official authentication owned by the host application.
///
/// Implementations may use OAuth sessions, a platform credential store, or a
/// remote runtime. They must not read CLI provider configuration files.
abstract interface class OfficialSubscriptionAuthReader {
  Future<ProviderCredentialScope?> read(ManagedProvider provider);
}

/// Official subscription transport boundary.
///
/// The client receives a request-scoped credential scope and returns a
/// provider-neutral response. It must not serialize or log the scope.
abstract interface class OfficialSubscriptionClient {
  Future<OfficialSubscriptionResponse> fetch(
    ManagedProvider provider, {
    required ProviderCredentialScope credentials,
    required DateTime now,
  });
}

class OfficialSubscriptionWindow {
  const OfficialSubscriptionWindow({
    required this.label,
    required this.kind,
    this.total,
    this.used,
    this.remaining,
    this.unit,
    this.currency,
    this.resetsAt,
  });

  final String label;
  final ProviderUsageMeasureKind kind;
  final String? total;
  final String? used;
  final String? remaining;
  final String? unit;
  final String? currency;
  final int? resetsAt;

  ProviderUsageMeasure toMeasure() => ProviderUsageMeasure(
    label: _validatedLabel,
    kind: kind,
    total: total,
    used: used,
    remaining: remaining,
    unit: unit,
    currency: currency,
    resetsAt: resetsAt,
  );

  String get _validatedLabel {
    if (label.trim().isEmpty ||
        total == null && used == null && remaining == null) {
      throw const FormatException('invalid official subscription window');
    }
    return label;
  }
}

class OfficialSubscriptionResponse {
  OfficialSubscriptionResponse({
    required Iterable<OfficialSubscriptionWindow> windows,
    this.staleAfter,
    this.adapterVersion,
  }) : windows = List.unmodifiable(windows);

  final List<OfficialSubscriptionWindow> windows;
  final Duration? staleAfter;
  final String? adapterVersion;
}

/// Shared implementation for official subscription adapters.
///
/// Provider-specific classes only supply stable IDs and injected boundary
/// implementations. The normalization rules stay identical across official
/// providers.
abstract class OfficialSubscriptionAdapter
    implements ManagedProviderUsageAdapter {
  const OfficialSubscriptionAdapter({
    required this.authReader,
    required this.client,
  });

  final OfficialSubscriptionAuthReader authReader;
  final OfficialSubscriptionClient client;

  String get officialProviderId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    if (provider.adapterId.trim() != id ||
        provider.kind != ManagedProviderKind.subscriptionQuota) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }

    final auth = await _readAuth(provider);
    final response = await _readResponse(provider, credentials: auth, now: now);
    if (response.windows.isEmpty) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }

    try {
      final measures = response.windows
          .map((window) => window.toMeasure())
          .toList(growable: false);
      return ProviderUsageSnapshot(
        providerId: provider.id,
        status: ProviderUsageStatus.ready,
        measures: measures,
        fetchedAt: now.millisecondsSinceEpoch,
        staleAt: response.staleAfter == null
            ? null
            : now.add(response.staleAfter!).millisecondsSinceEpoch,
        adapterVersion: response.adapterVersion,
      );
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
  }

  Future<ProviderCredentialScope> _readAuth(ManagedProvider provider) async {
    try {
      final auth = await authReader.read(provider);
      if (auth == null || auth.isEmpty) {
        throw const ManagedProviderUsageQueryError(
          ManagedProviderUsageQueryErrorCode.missingCredential,
        );
      }
      return auth;
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
  }

  Future<OfficialSubscriptionResponse> _readResponse(
    ManagedProvider provider, {
    required ProviderCredentialScope credentials,
    required DateTime now,
  }) async {
    try {
      return await client.fetch(provider, credentials: credentials, now: now);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }
  }
}
