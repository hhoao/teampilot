import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/catalog/catalog_mcp_handler.dart';
import 'package:teampilot/services/catalog/catalog_runtime.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';

void main() {
  late Directory tmp;
  late Directory workRoot;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('catalog_runtime_');
    workRoot = Directory.systemTemp.createTempSync('catalog_runtime_work_');
    final paths = AppPaths(tmp.path);
    AppStorage.installForTesting(
      filesystem: LocalFilesystem(
        pathContext: AppPaths.pathContextForDataRoot(paths.basePath),
      ),
      paths: paths,
      home: tmp.path,
      cwd: tmp.path,
    );
  });

  tearDown(() {
    AppStorage.resetForTesting();
    AppPathsBootstrapper.resetForTesting();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    if (workRoot.existsSync()) workRoot.deleteSync(recursive: true);
  });

  CatalogMcpSession mcpSession() => CatalogMcpSession(
    sessionId: 's1',
    workspaceId: 'ws1',
    workFs: LocalFilesystem(),
    allowedRoots: [workRoot.path],
  );

  Future<Map<String, Object?>> callTool({
    required CatalogRuntime runtime,
    required String name,
    required Map<String, Object?> arguments,
    required CatalogMcpSession session,
  }) async {
    final res = await runtime.handler.handle(
      JsonRpcRequest(
        id: 1,
        method: 'tools/call',
        params: {'name': name, 'arguments': arguments},
      ),
      session,
    );
    expect(res, isNotNull);
    expect(res!.result!['isError'], isFalse);
    final text = (res.result!['content'] as List).first['text'] as String;
    return jsonDecode(text) as Map<String, Object?>;
  }

  test(
    'assemble round-trips create_skill then list_installed without widgets',
    () async {
      final runtime = CatalogRuntime.assemble();
      final session = mcpSession();

      final created = await callTool(
        runtime: runtime,
        name: 'create_skill',
        arguments: {
          'name': 'Hello Skill',
          'directory': 'hello-skill',
          'body': 'Do the thing.',
        },
        session: session,
      );
      expect(created['ok'], isTrue);
      expect(created['ids'], ['local:hello-skill']);
      expect(created['restart_required'], isTrue);

      final listed = await callTool(
        runtime: runtime,
        name: 'list_installed',
        arguments: {'kind': 'skill'},
        session: session,
      );
      expect(listed['ok'], isTrue);
      final skill = listed['data'] is Map
          ? (listed['data'] as Map)['skill'] as Map<Object?, Object?>?
          : null;
      expect(skill?['boundIds'], contains('local:hello-skill'));
    },
  );

  test(
    'resolveSession uses findById and session folder paths as allowedRoots',
    () async {
      final sessions = SessionRepository();
      final workspace = await sessions.createWorkspace([
        WorkspaceFolder(path: workRoot.path),
      ]);
      final created = (await sessions.createSession(
        workspace.workspaceId,
      )).session;
      final runtime = CatalogRuntime.assemble(sessions: sessions);

      final resolved = await runtime.resolveSession(created.sessionId);
      expect(resolved, isNotNull);
      expect(resolved!.sessionId, created.sessionId);
      expect(resolved.workspaceId, workspace.workspaceId);
      expect(resolved.allowedRoots, created.folderPaths);
      expect(identical(resolved.workFs, AppStorage.fs), isTrue);

      expect(await runtime.resolveSession('missing-session'), isNull);
    },
  );
}
