import 'package:flutter/gestures.dart';
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
        height: 48,
        width: 600,
        child: GitGraphRowTile(
          row: makeRow('abc'),
          selected: false,
          onTap: () {},
        ),
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
        height: 48,
        width: 600,
        child: GitGraphRowTile(
          row: makeRow(
            'abc',
            refs: [
              const GitRefDecoration(GitRefDecorationKind.head, 'main'),
              const GitRefDecoration(GitRefDecorationKind.tag, 'v1'),
            ],
          ),
          selected: false,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('main'), findsOneWidget);
    expect(find.text('v1'), findsOneWidget);
  });

  testWidgets('commit row does not overflow with long metadata', (
    tester,
  ) async {
    await pump(
      tester,
      SizedBox(
        height: 48,
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

  testWidgets(
    'subject keeps remaining space; refs/author do not take equal flex',
    (tester) async {
      // Regression: wrapping refs/author/date in Flexible(flex:1) made them
      // fight the subject Expanded for equal shares, so messages looked uneven.
      const subject = 'subject-needs-most-of-the-row-width-here';
      await pump(
        tester,
        SizedBox(
          height: 48,
          width: 600,
          child: GitGraphRowTile(
            row: GitCommitRow(
              edges: const [GitGraphEdge(0, 0, 0)],
              node: const GitGraphNode(0, 0),
              hash: 'abc',
              parents: const ['p'],
              authorName: 'Ann',
              authorEmail: 'ann@x',
              authorDate: DateTime.utc(2026, 8, 25, 10, 30),
              subject: subject,
              refs: const [
                GitRefDecoration(
                  GitRefDecorationKind.localBranch,
                  'feature/agentic-team-generate-long',
                ),
              ],
            ),
            selected: false,
            onTap: () {},
          ),
        ),
      );

      final subjectWidth = tester.getSize(find.text(subject)).width;
      final authorWidth = tester.getSize(find.text('Ann')).width;
      expect(subjectWidth, greaterThan(250));
      expect(authorWidth, lessThan(60));
    },
  );

  testWidgets('columns are Date then Author then short hash', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 48,
        width: 700,
        child: GitGraphRowTile(
          row: makeRow('abcdef12deadbeef'),
          selected: false,
          onTap: () {},
        ),
      ),
    );
    expect(find.text('abcdef12'), findsOneWidget);
    final dateDx = tester.getTopLeft(find.textContaining('08/25')).dx;
    final authorDx = tester.getTopLeft(find.text('Ann')).dx;
    final hashDx = tester.getTopLeft(find.text('abcdef12')).dx;
    expect(dateDx, lessThan(authorDx));
    expect(authorDx, lessThan(hashDx));
  });

  testWidgets('commit hash tap invokes onCommitHashTap', (tester) async {
    var tapped = false;
    await pump(
      tester,
      SizedBox(
        height: 48,
        width: 700,
        child: GitGraphRowTile(
          row: makeRow('abcdef12deadbeef'),
          selected: false,
          onTap: () {},
          onCommitHashTap: () => tapped = true,
        ),
      ),
    );
    await tester.tap(find.text('abcdef12'));
    expect(tapped, isTrue);
  });

  testWidgets('tap fires callback', (tester) async {
    var tapped = false;
    await pump(
      tester,
      SizedBox(
        height: 48,
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

  testWidgets('lane painter spans the full row height for cross-row edges', (
    tester,
  ) async {
    // 回归：painter 曾被 vertical padding 内缩（32/40），相邻行之间留下 8px
    // 空白带，竖线呈虚线状。连线必须画满整行才能跨行连续。
    await pump(
      tester,
      SizedBox(
        width: 600,
        child: Column(
          children: [
            GitGraphRowTile(row: makeRow('a'), selected: false, onTap: () {}),
            GitGraphRowTile(row: makeRow('b'), selected: false, onTap: () {}),
          ],
        ),
      ),
    );

    final painters = find.descendant(
      of: find.byType(GitGraphRowTile),
      matching: find.byType(CustomPaint),
    );
    expect(painters, findsNWidgets(2));
    final top = tester.getRect(painters.at(0));
    final bottom = tester.getRect(painters.at(1));
    expect(top.top, 0);
    expect(top.bottom, bottom.top);
  });

  testWidgets('spacer painter shares the commit painter horizontal origin', (
    tester,
  ) async {
    // 回归：spacer 行没有 horizontalPadding，曲线整体左移 12px（≈ 一个
    // lane 宽），与提交行的竖线/节点接不上。
    await pump(
      tester,
      SizedBox(
        width: 600,
        child: Column(
          children: [
            GitGraphRowTile(row: makeRow('a'), selected: false, onTap: () {}),
            GitGraphSpacerTile(
              row: const GitGraphSpacerRow(edges: [GitGraphEdge(0, 0, 0)]),
            ),
          ],
        ),
      ),
    );

    final commitPainters = find.descendant(
      of: find.byType(GitGraphRowTile),
      matching: find.byType(CustomPaint),
    );
    final spacerPainters = find.descendant(
      of: find.byType(GitGraphSpacerTile),
      matching: find.byType(CustomPaint),
    );
    expect(commitPainters, findsOneWidget);
    expect(spacerPainters, findsOneWidget);
    final commitDx = tester.getTopLeft(commitPainters).dx;
    final spacerDx = tester.getTopLeft(spacerPainters).dx;
    expect(spacerDx, commitDx);
  });

  testWidgets('hover paints a highlight background', (tester) async {
    await pump(
      tester,
      SizedBox(
        height: 48,
        width: 600,
        child: GitGraphRowTile(
          row: makeRow('abc'),
          selected: false,
          onTap: () {},
        ),
      ),
    );

    Color? containerColor() {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GitGraphRowTile),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.color;
    }

    expect(containerColor(), isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();
    await gesture.moveTo(tester.getCenter(find.byType(GitGraphRowTile)));
    await tester.pumpAndSettle();

    expect(containerColor(), isNotNull);
  });
}
