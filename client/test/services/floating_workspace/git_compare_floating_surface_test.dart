import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_compare.dart';
import 'package:teampilot/services/floating_workspace/surfaces/git_compare_floating_surface.dart';

void main() {
  test('createTab builds stable tab from a GitCompareSpec payload', () {
    final surface = GitCompareFloatingSurface();
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('main'),
      right: const GitCompareWorkingTree(),
    );
    final tab = surface.createTab(workspaceId: 'ws1', payload: spec);
    expect(tab.surfaceId, 'gitCompare');
    expect(tab.id, spec.tabId);
    expect(tab.title, spec.tabTitle());
    expect(tab.payload, spec);
  });

  test('createTab reconstructs the spec from a tabId string payload', () {
    final surface = GitCompareFloatingSurface();
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('main'),
      right: const GitCompareWorkingTree(),
    );
    final tab = surface.createTab(workspaceId: 'ws1', payload: spec.tabId);
    expect(tab.id, spec.tabId);
    expect(tab.payload, isA<GitCompareSpec>());
    expect((tab.payload as GitCompareSpec).repoRoot, '/repo');
  });

  test('createTab falls back to an empty tab for unparseable payload', () {
    final surface = GitCompareFloatingSurface();
    final tab = surface.createTab(workspaceId: 'ws1', payload: 'bogus');
    expect(tab.surfaceId, 'gitCompare');
    expect(tab.payload, isNull);
  });
}
