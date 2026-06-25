import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team/claude_team_roster_service.dart';

import 'bus_mail_assertions.dart';

void main() {
  test('waitForBusMail matches msg row at correct jsonl path', () async {
    final tmp = await Directory.systemTemp.createTemp('bus_mail_assertions_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    const workspaceId = 'ws-1';
    const sessionId = 'sess-1';
    const memberId = 'team-lead';

    final layout = WorkspaceLayout(teampilotRoot: tmp.path);
    final mailRoot = layout.busMailDir(workspaceId, sessionId);
    await Directory(mailRoot).create(recursive: true);

    final slug = ClaudeTeamRosterService.safeClaudePathSegment(memberId);
    final mailFile = File(p.join(mailRoot, '$slug.jsonl'));
    await mailFile.writeAsString(
      '${jsonEncode({
        't': 'msg',
        'seq': 1,
        'id': 'm1',
        'from': 'worker-1',
        'to': memberId,
        'content': 'pong',
        'hop': 0,
        'createdAt': 1,
      })}\n',
    );

    final matched = await waitForBusMail(
      teampilotRoot: tmp.path,
      workspaceId: workspaceId,
      sessionId: sessionId,
      memberId: memberId,
      where: (row) =>
          row['from'] == 'worker-1' && row['content'] == 'pong',
    );

    expect(matched, isTrue);
    expect(
      busMailFilePath(
        teampilotRoot: tmp.path,
        workspaceId: workspaceId,
        sessionId: sessionId,
        memberId: memberId,
      ),
      mailFile.path,
    );
  });
}
