import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_compare.dart';

void main() {
  test('spec tabId stable for branch vs working tree', () {
    final a = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('api-dev'),
      right: const GitCompareWorkingTree(),
    );
    final b = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('api-dev'),
      right: const GitCompareWorkingTree(),
    );
    expect(a.tabId, b.tabId);
    expect(a.tabId, contains('ref:api-dev'));
    expect(a.tabId, contains('wt'));
  });

  test('title shortens full hash via titleOverride', () {
    final side = GitCompareRef(
      'abcdef0123456789',
      titleOverride: 'abcdef01',
    );
    expect(side.titleLabel(), 'abcdef01');
    expect(side.idKey, 'ref:abcdef0123456789');
  });
}
