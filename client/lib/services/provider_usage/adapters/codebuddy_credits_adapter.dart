import '../../../models/app_provider_config.dart';
import '../../../models/managed_provider.dart';
import '../../../models/provider_usage_snapshot.dart';
import '../../cli/codebuddy/provider/codebuddy_auth_store.dart';
import '../../io/filesystem.dart';
import '../managed_provider_cli_binding.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_subscription_parse.dart';

/// CodeBuddy credit balance.
///
/// The account realm lives in the CLI's per-provider auth document, so the
/// request host is read from there instead of a fixed preset URL. The endpoint
/// only needs the bearer token; `X-User-Id` is optional.
class CodebuddyCreditsUsageAdapter implements ManagedProviderUsageAdapter {
  CodebuddyCreditsUsageAdapter({
    required Filesystem fs,
    required String basePath,
  }) : _store = CodebuddyAuthStore(
         fs: fs,
         basePath: basePath,
         pathContext: fs.pathContext,
       );

  static const adapterId = 'codebuddy-credits';
  static const _summaryPath = '/billing/meter/get-user-resource-summary';

  /// Realms shipped by the CodeBuddy CLI product config. Anything else in a
  /// tampered auth file is refused rather than sent to an arbitrary host.
  static const _allowedDomains = <String>{
    'www.codebuddy.cn',
    'www.codebuddy.ai',
    'copilot.tencent.com',
    'staging-copilot.tencent.com',
    'staging-codebuddy.tencent.com',
    'www.workbuddy.cn',
    'www.workbuddy.ai',
  };

  final CodebuddyAuthStore _store;

  @override
  String get id => adapterId;

  @override
  Future<ProviderUsageSnapshot> fetch(
    ManagedProvider provider, {
    required ProviderCredentialResolver credentials,
    required ProviderUsageHttpClient http,
    required DateTime now,
  }) async {
    final rowId = managedProviderCliRowId(
      CliTool.codebuddy,
      provider.id.trim(),
    );
    final auth = await _store.readProviderAuth(rowId);
    final accessToken = _store.accessTokenFor(auth);
    if (accessToken == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.missingCredential,
      );
    }
    final uri = _summaryUri(auth?['domain']);
    if (uri == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.unsupported,
      );
    }

    final request = ProviderUsageHttpRequest(
      method: 'POST',
      uri: uri,
      headers: {
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: '{}',
    );

    late final ProviderUsageHttpResponse response;
    try {
      response = await http.send(request);
    } on ManagedProviderUsageQueryError {
      rethrow;
    } on Object {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.networkFailed,
      );
    }
    throwOfficialHttpStatus(response.statusCode);

    final json = decodeOfficialJsonObject(response.body);
    final code = json['code'];
    if (code is num && code.toInt() != 0) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }
    final data = json['data'];
    final remaining = data is Map ? _decimalText(data['TotalCredits']) : null;
    if (remaining == null) {
      throw const ManagedProviderUsageQueryError(
        ManagedProviderUsageQueryErrorCode.responseParseFailed,
      );
    }

    return ProviderUsageSnapshot(
      providerId: provider.id,
      status: ProviderUsageStatus.ready,
      measures: [
        ProviderUsageMeasure(
          label: 'Credits',
          kind: ProviderUsageMeasureKind.balance,
          remaining: remaining,
          unit: 'credits',
        ),
      ],
      fetchedAt: now.millisecondsSinceEpoch,
    );
  }

  static Uri? _summaryUri(Object? rawDomain) {
    final domain = rawDomain?.toString().trim().toLowerCase() ?? '';
    if (!_allowedDomains.contains(domain)) return null;
    return Uri(scheme: 'https', host: domain, path: _summaryPath);
  }

  static String? _decimalText(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(trimmed)) return trimmed;
      return null;
    }
    if (raw is num && raw.isFinite) return raw.toString();
    return null;
  }
}
