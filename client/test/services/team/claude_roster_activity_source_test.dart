import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/member_presence.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team/claude_roster_activity_source.dart';

void main() {
  late Directory tmp;
  late ClaudeRosterActivitySource source;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('roster_activity_');
    source = ClaudeRosterActivitySource(fs: LocalFilesystem());
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('readMemberWorking maps isActive false to idle', () async {
    final claudeDir = Directory('${tmp.path}/claude');
    final rosterDir = Directory('${claudeDir.path}/teams/my-team-1');
    await rosterDir.create(recursive: true);
    await File('${rosterDir.path}/config.json').writeAsString(
      jsonEncode({
        'members': [
          {'name': 'team-lead', 'isActive': true},
          {'name': 'dev', 'isActive': false},
        ],
      }),
    );

    final map = await source.readMemberWorking(
      claudeConfigDir: claudeDir.path,
      cliTeamName: 'my-team-1',
    );

    expect(map['team-lead'], isTrue);
    expect(map['dev'], isFalse);
    expect(map.containsKey('team-lead'), isTrue);
    expect(
      source.workloadForMember(memberId: 'dev', workingByName: map),
      MemberWorkload.idle,
    );
    expect(
      source.workloadForMember(memberId: 'team-lead', workingByName: map),
      MemberWorkload.working,
    );
  });

  test('readMemberWorking treats missing isActive as idle', () async {
    final claudeDir = Directory('${tmp.path}/claude2');
    final rosterDir = Directory('${claudeDir.path}/teams/my-team-2');
    await rosterDir.create(recursive: true);
    await File('${rosterDir.path}/config.json').writeAsString(
      jsonEncode({
        'members': [
          {'name': 'dev'},
        ],
      }),
    );

    final map = await source.readMemberWorking(
      claudeConfigDir: claudeDir.path,
      cliTeamName: 'my-team-2',
    );

    expect(map['dev'], isFalse);
    expect(
      source.workloadForMember(memberId: 'dev', workingByName: map),
      MemberWorkload.idle,
    );
  });
}
