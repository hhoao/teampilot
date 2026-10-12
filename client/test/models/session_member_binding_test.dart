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

  test('acp defaults false, omits JSON, round-trips true', () {
    const off = SessionMemberBinding(rosterMemberId: 'lead', taskId: 't1');
    expect(off.acp, isFalse);
    expect(off.toJson().containsKey('acp'), isFalse);
    expect(
      SessionMemberBinding.fromJson({
        'rosterMemberId': 'lead',
        'taskId': 't1',
      }).acp,
      isFalse,
    );

    const on = SessionMemberBinding(
      rosterMemberId: 'lead',
      taskId: 't1',
      acp: true,
    );
    expect(on.toJson()['acp'], isTrue);
    expect(SessionMemberBinding.fromJson(on.toJson()).acp, isTrue);

    final kept = on.withNativeSessionId('cursor', 'n1');
    expect(kept.acp, isTrue);
    expect(on, isNot(off));
    expect(on.hashCode, isNot(off.hashCode));
  });
}
