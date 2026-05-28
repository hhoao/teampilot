import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/cli_data_layout.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/session_team_counter.dart';

void main() {
  test('increments per teamId', () async {
    final dir = await Directory.systemTemp.createTemp('session_team_counter_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final fs = LocalFilesystem();
    final layout = CliDataLayout(teampilotRoot: dir.path, fs: fs);
    final counter = SessionTeamCounter(fs: fs, layout: layout);
    expect(await counter.nextCliTeamName('team-a'), 'team-a-1');
    expect(await counter.nextCliTeamName('team-a'), 'team-a-2');
    expect(await counter.nextCliTeamName('team-b'), 'team-b-1');
    expect(await counter.nextCliTeamName('default-team'), 'default-team-1');
  });
}
