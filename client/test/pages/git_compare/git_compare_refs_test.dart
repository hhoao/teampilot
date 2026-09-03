import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_compare/git_compare_refs.dart';

import '../../support/git_graph_test_fakes.dart';

void main() {
  group('gitCompareRefsForCommit', () {
    test('uses first local branch for compareRef and titleRef', () {
      final row = graphCommitRow(
        'abcdef1234567890',
        refs: const [
          GitRefDecoration(GitRefDecorationKind.tag, 'v1'),
          GitRefDecoration(GitRefDecorationKind.localBranch, 'feature'),
        ],
      );
      final refs = gitCompareRefsForCommit(row);
      expect(refs.compareRef, 'feature');
      expect(refs.titleRef, 'feature');
    });

    test('falls back to full hash and short hash when no local branch', () {
      final row = graphCommitRow('abcdef1234567890');
      final refs = gitCompareRefsForCommit(row);
      expect(refs.compareRef, 'abcdef1234567890');
      expect(refs.titleRef, 'abcdef12');
    });

    test('uses full hash as title when hash length <= 8', () {
      final row = graphCommitRow('deadbeef');
      final refs = gitCompareRefsForCommit(row);
      expect(refs.compareRef, 'deadbeef');
      expect(refs.titleRef, 'deadbeef');
    });
  });
}
