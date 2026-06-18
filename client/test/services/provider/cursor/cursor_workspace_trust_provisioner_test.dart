import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust.dart';
import 'package:teampilot/services/provider/cursor/cursor_workspace_trust_provisioner.dart';

import '../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late CursorWorkspaceTrustProvisioner provisioner;

  setUp(() {
    fs = InMemoryFilesystem();
    provisioner = CursorWorkspaceTrustProvisioner(fs: fs);
  });

  group('CursorWorkspaceTrustProvisioner', () {
    test('workspacePathKeys dedupes working directory variants', () {
      final keys = CursorWorkspaceTrustProvisioner.workspacePathKeys(
        workingDirectory: '/workspace/workspace',
        additionalDirectories: const ['/workspace/workspace', ''],
      );
      expect(keys, {'/workspace/workspace'});
    });

    test('provision writes trust marker under homeRoot', () async {
      const home = '/fake/home';
      const workspace = '/home/hhoa/Document/testmixed';

      await provisioner.provision(
        homeRoot: home,
        workspacePaths: [workspace],
      );

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        home,
        workspace,
        pathContext: fs.pathContext,
      );
      expect((await fs.stat(trustPath)).isFile, isTrue);
      final trust = jsonDecode((await fs.readString(trustPath))!) as Map;
      expect(trust['workspacePath'], workspace);
      expect(trust['trustMethod'], CursorWorkspaceTrust.trustMethod);
    });

    test('provisionLaunchWorkspaces writes markers for each path key', () async {
      const home = '/fake/home';
      const workspace = '/workspace/a';
      const extra = '/workspace/b';

      await provisioner.provisionLaunchWorkspaces(
        homeRoot: home,
        workingDirectory: workspace,
        additionalDirectories: [extra],
      );

      for (final path in [workspace, extra]) {
        final trustPath = CursorWorkspaceTrust.trustMarkerPath(
          home,
          path,
          pathContext: fs.pathContext,
        );
        expect((await fs.stat(trustPath)).isFile, isTrue);
      }
    });

    test('provision is a no-op for empty home or workspace list', () async {
      await provisioner.provision(homeRoot: '', workspacePaths: ['/x']);
      await provisioner.provision(homeRoot: '/home', workspacePaths: const []);
      expect(fs.files, isEmpty);
    });

    test('trust marker path uses slugified workspace dir', () async {
      const home = '/fake/home';
      const workspace = '/home/hhoa/git/hhoa/teampilot';

      await provisioner.provision(
        homeRoot: home,
        workspacePaths: [workspace],
      );

      final trustPath = CursorWorkspaceTrust.trustMarkerPath(
        home,
        workspace,
        pathContext: fs.pathContext,
      );
      expect((await fs.stat(trustPath)).isFile, isTrue);
    });
  });
}
