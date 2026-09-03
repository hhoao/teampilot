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

  test('tryParseTabId round-trips ref vs working tree', () {
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('main'),
      right: const GitCompareWorkingTree(),
    );
    final parsed = GitCompareSpec.tryParseTabId(spec.tabId);
    expect(parsed, isNotNull);
    expect(parsed!.repoRoot, '/repo');
    expect(parsed.left, const GitCompareRef('main'));
    expect(parsed.right, const GitCompareWorkingTree());
  });

  test('tryParseTabId round-trips ref vs ref', () {
    final spec = GitCompareSpec(
      repoRoot: '/repo',
      left: const GitCompareRef('abc123'),
      right: const GitCompareRef('def456'),
    );
    final parsed = GitCompareSpec.tryParseTabId(spec.tabId);
    expect(parsed, isNotNull);
    expect(parsed!.left, const GitCompareRef('abc123'));
    expect(parsed.right, const GitCompareRef('def456'));
  });

  test('tryParseTabId rejects malformed ids', () {
    expect(GitCompareSpec.tryParseTabId('not-a-tab-id'), isNull);
    expect(GitCompareSpec.tryParseTabId('gitCompare:/repo|wt'), isNull);
    expect(
      GitCompareSpec.tryParseTabId('gitCompare:/repo|bogus|wt'),
      isNull,
    );
  });
}
