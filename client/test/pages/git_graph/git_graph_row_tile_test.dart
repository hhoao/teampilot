import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/pages/git_graph/git_graph_row_tile.dart';

GitCommitRow makeRow(String hash, {List<GitRefDecoration> refs = const []}) =>
    GitCommitRow(
      edges: const [GitGraphEdge(0, 0, 0)],
      node: const GitGraphNode(0, 0),
      hash: hash,
      parents: const ['p'],
      authorName: 'Ann',
      authorEmail: 'ann@x',
      authorDate: DateTime.utc(2026, 8, 25, 10, 30),
      subject: 'add feature',
      refs: refs,
    );

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
}

void main() {
  testWidgets('commit row renders subject, author and date', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 26,
        width: 600,
        child: GitGraphRowTile(row: makeRow('abc'), selected: false, onTap: () {}),
      ),
    );
    expect(find.text('add feature'), findsOneWidget);
    expect(find.textContaining('Ann'), findsOneWidget);
    expect(find.textContaining('08/25'), findsOneWidget);
  });

  testWidgets('ref decorations render as chips', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 26,
        width: 600,
        child: GitGraphRowTile(
          row: makeRow('abc', refs: [
            const GitRefDecoration(GitRefDecorationKind.head, 'main'),
            const GitRefDecoration(GitRefDecorationKind.tag, 'v1'),
          ]),
          selected: false,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('main'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
  });

  testWidgets('commit row does not overflow with long metadata', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 26,
        width: 220,
        child: GitGraphRowTile(
          row: GitCommitRow(
            edges: const [GitGraphEdge(0, 0, 0)],
            node: const GitGraphNode(0, 0),
            hash: 'abc',
            parents: const ['p'],
            authorName: 'A very long author name',
            authorEmail: 'ann@x',
            authorDate: DateTime.utc(2026, 8, 25, 10, 30),
            subject: 'a very long commit subject that needs truncating',
            refs: const [
              GitRefDecoration(
                GitRefDecorationKind.localBranch,
                'feature/with-a-long-name',
              ),
            ],
          ),
          selected: false,
          onTap: () {},
        ),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('tap fires callback', (tester) async {
    var tapped = false;
    await pump(
      tester,
      SizedBox(
        height: 26,
        width: 600,
        child: GitGraphRowTile(
          row: makeRow('abc'),
          selected: false,
          onTap: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.text('add feature'));
    expect(tapped, isTrue);
  });
}
