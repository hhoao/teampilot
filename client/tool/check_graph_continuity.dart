// 一次性校验脚本：直接运行 `git log --graph`（与 GitHistoryService 相同参数），
// 把输出喂给 GitGraphParser，检查相邻行的连线端点 slot 是否衔接
// （视觉上无断线/悬空）。用法: dart run tool/check_graph_continuity.dart [repoDir]
// 说明：lane 起点（分支头/stash）与终点（root/无父提交）是合法的行首/行尾悬空。
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:teampilot/services/git/parser/git_graph_parser.dart';

void main(List<String> args) async {
  final dir = args.isNotEmpty ? args[0] : '.';
  const fieldSep = '\x1f';
  final format = '%x1e'
      '%H$fieldSep%P$fieldSep%an$fieldSep%ae$fieldSep%at$fieldSep%d$fieldSep%s';
  final result = await Process.run('git', [
    'log', '--all', '--date-order', '--max-count', '400',
    '--pretty=format:$format', '--graph',
  ], workingDirectory: dir, stdoutEncoding: utf8);
  if (result.exitCode != 0) {
    stderr.write('git failed: ${result.stderr}');
    exitCode = 1;
    return;
  }
  final rows = GitGraphParser.parse(result.stdout as String);
  var breaks = 0;
  for (var i = 0; i + 1 < rows.length; i++) {
    final bottom = rows[i].edges.map((e) => e.toSlot).toSet();
    final top = rows[i + 1].edges.map((e) => e.fromSlot).toSet();
    final bottomOnly = bottom.difference(top).toList()..sort();
    final topOnly = top.difference(bottom).toList()..sort();
    if (bottomOnly.isNotEmpty || topOnly.isNotEmpty) {
      breaks++;
      print('rows $i->${i + 1}: bottom-only=$bottomOnly top-only=$topOnly');
    }
  }
  print('rows=${rows.length} broken-boundaries=$breaks');
}
