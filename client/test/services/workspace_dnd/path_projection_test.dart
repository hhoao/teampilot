import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workspace_dnd/path_namespace.dart';
import 'package:teampilot/services/workspace_dnd/path_projection.dart';
import 'package:teampilot/services/workspace_dnd/runtime_target.dart';
import 'package:teampilot/services/workspace_dnd/workspace_file_ref.dart';

WorkspaceFileRef _ref(String path, PathNamespace ns) =>
    WorkspaceFileRef(nativePath: path, namespace: ns, isDirectory: false);

void main() {
  const projection = PathProjection();

  test('same namespace passes the path through unchanged', () {
    final result = projection.project(
      _ref('/home/u/x.dart', const PathNamespace.localPosix()),
      const RuntimeTarget.localPosix(),
    );
    expect(result, isA<ProjectedPath>());
    expect((result as ProjectedPath).projectedPath, '/home/u/x.dart');
  });

  test('local Windows path projects to a WSL /mnt path for a WSL target', () {
    final result = projection.project(
      _ref(r'C:\Users\me\x.dart', const PathNamespace.localWindows()),
      const RuntimeTarget.wsl(),
    );
    expect(result, isA<ProjectedPath>());
    expect((result as ProjectedPath).projectedPath, '/mnt/c/Users/me/x.dart');
  });

  test('WSL /mnt path projects back to a Windows path for a native target', () {
    final result = projection.project(
      _ref('/mnt/c/Users/me/x.dart', const PathNamespace.localPosix()),
      const RuntimeTarget.localWindows(),
    );
    expect(result, isA<ProjectedPath>());
    expect((result as ProjectedPath).projectedPath, r'C:\Users\me\x.dart');
  });

  test('local file dropped on an SSH target is cross-namespace', () {
    final result = projection.project(
      _ref('/home/u/x.dart', const PathNamespace.localPosix()),
      const RuntimeTarget.ssh(),
    );
    expect(result, isA<CrossNamespacePath>());
  });

  test('remote file dropped on an SSH target stays same-host', () {
    final result = projection.project(
      _ref('/srv/app/x.dart', const PathNamespace.ssh()),
      const RuntimeTarget.ssh(),
    );
    expect(result, isA<ProjectedPath>());
    expect((result as ProjectedPath).projectedPath, '/srv/app/x.dart');
  });
}
