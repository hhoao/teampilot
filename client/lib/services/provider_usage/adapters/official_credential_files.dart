import 'dart:convert';

import '../../io/filesystem.dart';
import '../managed_provider_usage_adapter.dart';

Future<Map<String, Object?>?> readOfficialCredentialJson(
  Filesystem fs,
  String path,
) async {
  final bytes = await fs.readBytes(path);
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    return decoded.map((key, value) => MapEntry(key.toString(), value));
  } on Object {
    return null;
  }
}

Never missingOfficialCredential() {
  throw const ManagedProviderUsageQueryError(
    ManagedProviderUsageQueryErrorCode.missingCredential,
  );
}

class ManagedProviderAccessTokenScope implements ProviderCredentialScope {
  ManagedProviderAccessTokenScope({required this.accessToken, this.accountId});

  final String accessToken;
  final String? accountId;

  @override
  bool get isEmpty => accessToken.isEmpty;

  @override
  Iterable<String> get fields => [
    'accessToken',
    if (accountId != null && accountId!.isNotEmpty) 'accountId',
  ];

  @override
  String? valueFor(String field) => switch (field) {
    'accessToken' => accessToken,
    'accountId' => accountId,
    _ => null,
  };

  @override
  String toString() => 'ManagedProviderAccessTokenScope(<redacted>)';
}
