import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/opencode/opencode_data_layout.dart';
import 'package:teampilot/services/provider/opencode/opencode_provider_credentials_service.dart';

void main() {
  late Directory root;
  late OpencodeProviderCredentialsService service;
  const layout = OpencodeDataLayout();

  setUp(() async {
    root = await Directory.systemTemp.createTemp('opencode-cred-');
    service = OpencodeProviderCredentialsService(
      fs: LocalFilesystem(),
      basePath: root.path,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('imports provider entry from global auth.json', () async {
    final home = await Directory.systemTemp.createTemp('opencode-home-');
    try {
      final dataHome = layout.globalDataHome(home.path);
      await Directory(dataHome).create(recursive: true);
      await File(layout.authJsonPath(dataHome)).writeAsString(
        jsonEncode({
          'openai': {'type': 'api', 'key': 'sk-test'},
          'anthropic': {'type': 'api', 'key': 'sk-other'},
        }),
      );

      final ok = await service.importFromGlobal(
        'openai',
        homeDirectory: home.path,
      );
      expect(ok, isTrue);
      expect((await service.probe('openai')).isReady, isTrue);
      expect((await service.probe('anthropic')).isReady, isFalse);

      final stored = await File(
        layout.providerAuthJsonPath(
          p.join(root.path, 'providers', 'opencode', 'openai'),
        ),
      ).readAsString();
      expect(stored, contains('sk-test'));
      expect(stored, isNot(contains('anthropic')));
    } finally {
      await home.delete(recursive: true);
    }
  });
}
