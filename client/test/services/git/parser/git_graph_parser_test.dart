import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/git_graph.dart';
import 'package:teampilot/services/git/parser/git_graph_parser.dart';

const String sep = '\x1e'; // record 分隔
const String f = '\x1f'; // 字段分隔

String row(String graph, List<String> fields) => '$graph$sep${fields.join(f)}';

void main() {
  group('GitGraphParser.parse', () {
    test('linear history: straight edges, node lanes, parents', () {
      final rows = GitGraphParser.parse([
        row('* ', ['c2', 'c1', 'A', 'a@x', '1000', '', 'second']),
        row('* ', ['c1', '', 'A', 'a@x', '900', '', 'first']),
      ].join('\n'));
      expect(rows, hasLength(2));
      final first = rows[0] as GitCommitRow;
      expect(first.node.lane, 0);
      expect(first.parents, ['c1']);
      expect(first.subject, 'second');
      expect(first.edges.single.isStraight, isTrue);
      expect(rows[1], isA<GitCommitRow>());
    });

    test('fork with backslash spacer carries curve 0->1; decorations on root',
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
      expect(fork.edges.any((e) => e.fromLane == 0 && e.toLane == 1), isTrue);

      final branch = rows[2] as GitCommitRow;
      expect(branch.node.lane, 1);
      final side = rows[3] as GitCommitRow;
      expect(side.node.lane, 0);

      final root = rows[5] as GitCommitRow;
      expect(root.refs.single.kind, GitRefDecorationKind.head);
      expect(root.refs.single.name, 'main');
    });

    test('merge-in |/ curves from lane1 down to lane0', () {
      final rows = GitGraphParser.parse('|/');
      expect(rows.single, isA<GitGraphSpacerRow>());
      expect(
        rows.single.edges.any((e) => e.fromLane == 1 && e.toLane == 0),
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
      final curve =
          rows[1].edges.firstWhere((e) => !e.isStraight);
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
      expect(curves.map((e) => (e.fromLane, e.toLane)),
          containsAll([(0, 1), (1, 2)]));
    });
  });
}
