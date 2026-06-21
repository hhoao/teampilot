import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('worktreePathFor → <root>/worktrees/<repo>/<branch>', () {
    final layout = WorkspaceLayout(
      teampilotRoot: '/data',
      fs: InMemoryFilesystem(),
    );
    expect(
      layout.worktreePathFor(repoName: 'teampilot', branch: 'main'),
      '/data/worktrees/teampilot/main',
    );
  });

  test('worktreePathFor keeps slashes in branch as nested dirs', () {
    final layout = WorkspaceLayout(
      teampilotRoot: '/data',
      fs: InMemoryFilesystem(),
    );
    expect(
      layout.worktreePathFor(repoName: 'teampilot', branch: 'feat/x'),
      '/data/worktrees/teampilot/feat/x',
    );
  });
}
