import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/provider/codex/codex_provider_credentials_service.dart';

void main() {
  late Directory root;
  late CodexProviderCredentialsService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('codex-cred-');
    service = CodexProviderCredentialsService(
      fs: LocalFilesystem(),
      basePath: root.path,
    );
  });

  tearDown(() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  });

  test('probe and import from global auth.json', () async {
    final home = await Directory.systemTemp.createTemp('codex-home-');
    try {
      final codexDir = Directory(p.join(home.path, '.codex'));
      await codexDir.create(recursive: true);
      await File(p.join(codexDir.path, 'auth.json')).writeAsString(
        jsonEncode({'OPENAI_API_KEY': 'sk-live'}),
      );

      expect((await service.probe('openai-official')).isReady, isFalse);

      final ok = await service.importFromGlobal(
        'openai-official',
        homeDirectory: home.path,
      );
      expect(ok, isTrue);
      expect((await service.probe('openai-official')).isReady, isTrue);
    } finally {
      await home.delete(recursive: true);
    }
  });
}
