import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/parser/git_graph_parser.dart';

const String sep = '\x1e'; // record 分隔
const String f = '\x1f'; // 字段分隔

String row(String graph, List<String> fields) => '$graph$sep${fields.join(f)}';

void main() {
  group('GitGraphParser.parse', () {
    test('linear history: straight edges, node slots, parents', () {
      final rows = GitGraphParser.parse([
        row('* ', ['c2', 'c1', 'A', 'a@x', '1000', '', 'second']),
        row('* ', ['c1', '', 'A', 'a@x', '900', '', 'first']),
      ].join('\n'));
      expect(rows, hasLength(2));
      final first = rows[0] as GitCommitRow;
      expect(first.node.slot, 0);
      expect(first.parents, ['c1']);
      expect(first.subject, 'second');
      expect(first.edges.single.isStraight, isTrue);
      expect(rows[1], isA<GitCommitRow>());
    });

    test('fork with backslash spacer carries curve 0->2; decorations on root',
        () {
      final rows = GitGraphParser.parse(
        [
          row('* ', ['m', 'a b', 'M', 'm@x', '1000', '', 'merge']),
          '|\\',
          row('| * ', ['b', 'r', 'B', 'b@x', '990', '', 'branch']),
          row('* | ', ['a', 'r', 'A', 'a@x', '995', '', 'side']),
          '|/',
          row('* ', ['r', '', 'R', 'r@x', '900', '(HEAD -> main)', 'root']),
        ].join('\n'),
        remotePrefixes: {'origin/'},
      );
      expect(rows.whereType<GitGraphSpacerRow>(), hasLength(2));
      final fork = rows[1];
      expect(fork.edges.any((e) => e.fromSlot == 0 && e.toSlot == 2), isTrue);

      final branch = rows[2] as GitCommitRow;
      expect(branch.node.slot, 2);
      final side = rows[3] as GitCommitRow;
      expect(side.node.slot, 0);

      final root = rows[5] as GitCommitRow;
      expect(root.refs.single.kind, GitRefDecorationKind.head);
      expect(root.refs.single.name, 'main');
    });

    test('merge-in |/ curves from lane1 down to lane0 (slots 2->0)', () {
      final rows = GitGraphParser.parse('|/');
      expect(rows.single, isA<GitGraphSpacerRow>());
      expect(
        rows.single.edges.any((e) => e.fromSlot == 2 && e.toSlot == 0),
        isTrue,
      );
    });

    test('timestamp becomes UTC DateTime; malformed rows skipped', () {
      final rows = GitGraphParser.parse([
        row('* ', ['h1', '', 'N', 'n@x', '1700000000', '', 's']),
        '*$sep broken',
      ].join('\n'));
      expect(rows, hasLength(1));
      expect(
        (rows.single as GitCommitRow).authorDate,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000, isUtc: true),
      );
    });

    test('lane colors assigned in first-touch order across rows', () {
      final rows = GitGraphParser.parse(
        [
          row('* ', ['m', 'a b', 'M', 'm@x', '10', '', 'm']),
          '|\\',
          row('| * ', ['b', 'r', 'B', 'b@x', '9', '', 'b']),
          row('* | ', ['a', 'r', 'A', 'a@x', '8', '', 'a']),
          row('* ', ['r', '', 'R', 'r@x', '7', '', 'r']),
        ].join('\n'),
      );
      final merge = rows[0] as GitCommitRow;
      expect(merge.node.colorIndex, 0);
      final curve = rows[1].edges.firstWhere((e) => !e.isStraight);
      expect(curve.colorIndex, 1);
    });

    test('octopus row parses multiple outgoing curves without crash', () {
      final rows = GitGraphParser.parse(
        [
          row('*-.   ', ['m', 'a b c', 'M', 'm@x', '10', '', 'octopus']),
          '|\\ \\',
          row('| | * ', ['c', 'r', 'C', 'c@x', '9', '', 'c']),
        ].join('\n'),
      );
      final curves = rows
          .expand((r) => r.edges)
          .where((e) => !e.isStraight)
          .toList();
      expect(curves.map((e) => (e.fromSlot, e.toSlot)),
          containsAll([(0, 2), (2, 4)]));
    });

    test('lane-crossing | |/ + |/| keeps line color and routes via gap', () {
      // 回归：右侧分支向左汇入 lane0 途中横穿 lane1（git 的 | |/ + |/| 折叠）。
      // 旧实现把第二段画在 lane1 中心并取 lane1 的颜色，视觉上像换线/分叉。
      final rows = GitGraphParser.parse([
        row('| | * ', ['x', 't', 'X', 'x@x', '10', '', 'x']),
        '| |/',
        '|/|',
        row('* | ', ['t', 't3', 'T', 't@x', '9', '', 't']),
      ].join('\n'));
      final nodeColor = (rows[0] as GitCommitRow).node.colorIndex;

      final first = rows[1].edges.firstWhere((e) => !e.isStraight);
      expect((first.fromSlot, first.toSlot), (4, 3));
      expect(first.colorIndex, nodeColor);

      final second = rows[2].edges.firstWhere((e) => !e.isStraight);
      expect((second.fromSlot, second.toSlot), (3, 0));
      expect(second.colorIndex, nodeColor);

      // 被穿越的 lane1 竖线保持自己的颜色。
      final resident = rows[2].edges.firstWhere(
        (e) => e.isStraight && e.fromSlot == 2,
      );
      expect(resident.colorIndex, isNot(nodeColor));
    });

    test('swap row " / " emits two crossing edges (git replace topology)', () {
      // 回归：git replace 改写父子关系时，两条 lane 线在一行内交换位置，
      // ASCII 只画一个 '/'。旧实现只画左移线，两端节点悬空。
      final rows = GitGraphParser.parse([
        row('* | ', ['a', 'b', 'A', 'a@x', '10', '', 'a']),
        ' / ',
        row('| * ', ['b', 'c', 'B', 'b@x', '9', '', 'b']),
      ].join('\n'));
      final spacer = rows[1];
      expect(
        spacer.edges.any((e) => e.fromSlot == 0 && e.toSlot == 2),
        isTrue,
      );
      expect(
        spacer.edges.any((e) => e.fromSlot == 2 && e.toSlot == 0),
        isTrue,
      );

      // 交换后两条线各自沿用原颜色：lane0 竖线现在承载原 lane1 线的颜色。
      final after = rows[2] as GitCommitRow;
      final before = rows[0] as GitCommitRow;
      final lane0After = after.edges.firstWhere((e) => e.isStraight).colorIndex;
      final lane1Before = before.edges
          .firstWhere((e) => e.isStraight && e.fromSlot == 2)
          .colorIndex;
      expect(lane0After, lane1Before);
    });
  });
}
