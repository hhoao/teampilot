import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/session_member_binding.dart';

void main() {
  test('round-trips json', () {
    const b = SessionMemberBinding(rosterMemberId: 'm1', taskId: 'uuid-1');
    final json = b.toJson();
    expect(SessionMemberBinding.fromJson(json), b);
  });
}
