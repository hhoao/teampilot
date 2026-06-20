import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/utils/trusted_project_paths.dart';
import 'package:teampilot/utils/workspace_path_utils.dart';

void main() {
  test('findCanonicalGitRoot returns repo root when cwd is nested', () async {
    final root = await Directory.systemTemp.createTemp('trust_git_root_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    await Directory('${root.path}/.git').create();
    final nested = Directory('${root.path}/client/lib');
    await nested.create(recursive: true);

    final fs = LocalFilesystem();
    expect(
      await findCanonicalGitRoot(fs, nested.path),
      root.path,
    );
  });

  test('collectTrustedProjectKeys includes git root for nested path', () async {
    final root = await Directory.systemTemp.createTemp('trust_git_keys_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    await Directory('${root.path}/.git').create();
    final nested = Directory('${root.path}/pkg/src');
    await nested.create(recursive: true);

    final fs = LocalFilesystem();
    final keys = await collectTrustedProjectKeys(
      fs: fs,
      directories: [nested.path],
    );

    expect(workspacePathsContains(keys, root.path), isTrue);
    expect(workspacePathsContains(keys, nested.path), isTrue);
  });
}
