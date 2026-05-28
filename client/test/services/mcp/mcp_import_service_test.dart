import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/mcp/mcp_import_service.dart';

void main() {
  late Directory home;
  late McpImportService importService;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('mcp_import_test_');
    importService = McpImportService(
      fs: LocalFilesystem(),
      homeDirectory: home.path,
    );
  });

  tearDown(() async {
    if (await home.exists()) await home.delete(recursive: true);
  });

  test('reads mcpServers from ~/.claude.json', () async {
    await File(p.join(home.path, '.claude.json')).writeAsString(
      jsonEncode({
        'mcpServers': {
          'fetch': {'type': 'stdio', 'command': 'npx'},
        },
      }),
    );

    final preview = await importService.previewAgainst(const []);
    expect(preview.newServers, hasLength(1));
    expect(preview.newServers.first.name, 'fetch');
    expect(preview.newServers.first.importedFrom, 'claude-user');
  });
}
