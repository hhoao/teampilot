import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';

void main() {
  test('typeId round-trips; defaults to the instance id when absent', () {
    const b = SessionMemberBinding(
        rosterMemberId: 'builder-0', typeId: 'builder', taskId: 't1');
    final back = SessionMemberBinding.fromJson(b.toJson());
    expect(back.rosterMemberId, 'builder-0');
    expect(back.typeId, 'builder');
    expect(back.taskId, 't1');

    // legacy json without typeId falls back to the instance id
    final legacy = SessionMemberBinding.fromJson(
        {'rosterMemberId': 'reviewer', 'taskId': 't2'});
    expect(legacy.typeId, 'reviewer');
  });
}
