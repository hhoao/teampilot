import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/parser/git_decoration_parser.dart';

void main() {
  group('parseGitDecorations', () {
    test('parses HEAD branch, remote and tag', () {
      final refs = parseGitDecorations(
        '(HEAD -> main, origin/main, tag: v1.0)',
        remotePrefixes: const {'origin/'},
      );
      expect(refs, const [
        GitRefDecoration(GitRefDecorationKind.head, 'main'),
        GitRefDecoration(GitRefDecorationKind.remoteBranch, 'origin/main'),
        GitRefDecoration(GitRefDecorationKind.tag, 'v1.0'),
      ]);
    });

    test('detached HEAD alone', () {
      expect(parseGitDecorations('(HEAD)'), const [
        GitRefDecoration(GitRefDecorationKind.head, ''),
      ]);
    });

    test('local branch with slash stays local when not a known remote prefix',
        () {
      final refs =
          parseGitDecorations('(feature/x)', remotePrefixes: {'origin/'});
      expect(refs.single.kind, GitRefDecorationKind.localBranch);
      expect(refs.single.name, 'feature/x');
    });

    test('falls back to origin/ heuristic without prefixes', () {
      final refs = parseGitDecorations('(origin/main)');
      expect(refs.single.kind, GitRefDecorationKind.remoteBranch);
    });

    test('empty or missing parens yield empty list', () {
      expect(parseGitDecorations(''), isEmpty);
      expect(parseGitDecorations('no-decor'), isEmpty);
      expect(parseGitDecorations('()'), isEmpty);
    });
  });
}
