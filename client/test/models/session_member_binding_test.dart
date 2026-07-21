import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('typeId round-trips; defaults to the instance id when absent', () {
    const b = SessionMemberBinding(
      rosterMemberId: 'builder-0',
      typeId: 'builder',
      taskId: 't1',
    );
    final back = SessionMemberBinding.fromJson(b.toJson());
    expect(back.rosterMemberId, 'builder-0');
    expect(back.typeId, 'builder');
    expect(back.taskId, 't1');

    // legacy json without typeId falls back to the instance id
    final legacy = SessionMemberBinding.fromJson({
      'rosterMemberId': 'reviewer',
      'taskId': 't2',
    });
    expect(legacy.typeId, 'reviewer');
  });

  test('cli round-trips; absent key is null', () {
    const withCli = SessionMemberBinding(
      rosterMemberId: 'team-lead',
      taskId: 't1',
      cli: CliTool.claude,
    );
    final back = SessionMemberBinding.fromJson(withCli.toJson());
    expect(back.cli, CliTool.claude);
    expect(withCli.toJson()['cli'], 'claude');

    final legacy = SessionMemberBinding.fromJson({
      'rosterMemberId': 'team-lead',
      'taskId': 't2',
    });
    expect(legacy.cli, isNull);

    final kept = withCli.withNativeSessionId('cursor', 'native-1');
    expect(kept.cli, CliTool.claude);
    expect(kept.nativeSessionIds['cursor'], 'native-1');
  });
}
