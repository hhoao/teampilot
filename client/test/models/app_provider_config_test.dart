import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';

void main() {
  test('credentialLink round-trips through json', () {
    const provider = AppProviderConfig(
      id: 'deepseek',
      cli: CliTool.claude,
      name: 'DeepSeek',
      credentialLink: 'managed-1',
    );
    final decoded = AppProviderConfig.fromJson(
      Map<String, Object?>.from(jsonDecode(jsonEncode(provider.toJson()))),
    );
    expect(decoded.credentialLink, 'managed-1');
  });

  test('credentialLink defaults to empty and does not serialize when empty',
      () {
    const provider = AppProviderConfig(
      id: 'x',
      cli: CliTool.claude,
      name: 'X',
    );
    expect(provider.credentialLink, '');
    expect(provider.toJson().containsKey('credentialLink'), isFalse);
    // Pre-feature files (no credentialLink key) round-trip unchanged.
    final decoded = AppProviderConfig.fromJson({
      'id': 'x',
      'cli': 'claude',
      'name': 'X',
    });
    expect(decoded.credentialLink, '');
  });

  test('copyWith updates and clears credentialLink', () {
    const provider = AppProviderConfig(
      id: 'x',
      cli: CliTool.claude,
      name: 'X',
      credentialLink: 'a',
    );
    expect(provider.copyWith(credentialLink: 'b').credentialLink, 'b');
    expect(provider.copyWith(credentialLink: '').credentialLink, '');
  });
}
