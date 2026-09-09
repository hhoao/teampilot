import 'package:flutter_test/flutter_test.dart';

import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/content_search_slices.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../../support/test_runtime_context.dart';

/// The builder only reads `tools.context.filesystem`, so any working
/// RuntimeContext works; use the shared native test helper.
WorkspaceTargetSlice _slice(String targetId, List<String> roots) {
  final tools = WorkspaceToolsContext(
    targetId: targetId,
    context: testRuntimeContext('/home'),
  );
  return WorkspaceTargetSlice(targetId: targetId, tools: tools, roots: roots);
}

void main() {
  test('one slice per root per target, in scope order', () {
    final scope = WorkspaceToolsScopeState(
      targetSlices: [
        _slice('local', ['/ws/a', '/ws/b']),
        _slice('ssh:one', ['/remote/c']),
      ],
      resolving: false,
    );
    final slices = contentSearchSlicesForScope(
      scope: scope,
      cwd: '/ws/a',
      fallbackFs: LocalFilesystem(),
    );
    expect(slices.map((s) => s.root), ['/ws/a', '/ws/b', '/remote/c']);
    expect(slices.map((s) => s.label), ['a', 'b', 'c']);
  });

  test('falls back to a single cwd slice when no target resolved', () {
    final scope = const WorkspaceToolsScopeState(resolving: true);
    final slices = contentSearchSlicesForScope(
      scope: scope,
      cwd: '/ws/a',
      fallbackFs: LocalFilesystem(),
    );
    expect(slices, hasLength(1));
    expect(slices.single.root, '/ws/a');
    expect(slices.single.label, 'a');
  });

  test('skips empty roots and empty cwd without emitting slices', () {
    final scope = WorkspaceToolsScopeState(
      targetSlices: [_slice('local', ['', '/ws/a', '  '])],
      resolving: false,
    );
    final slices = contentSearchSlicesForScope(
      scope: scope,
      cwd: '/ws/a',
      fallbackFs: LocalFilesystem(),
    );
    expect(slices.map((s) => s.root), ['/ws/a']);

    final emptyScope = WorkspaceToolsScopeState(
      targetSlices: [_slice('local', [''])],
      resolving: false,
    );
    expect(
      contentSearchSlicesForScope(
        scope: emptyScope,
        cwd: ' ',
        fallbackFs: LocalFilesystem(),
      ),
      isEmpty,
    );
  });
}
