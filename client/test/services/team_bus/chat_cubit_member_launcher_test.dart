import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/chat_cubit_member_launcher.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

class _Spy implements MemberMaterializer {
  final calls = <String>[];
  @override
  Future<void> materializeMember(String s, String m, String b) async {
    calls.add('materialize:$s:$m:$b');
  }
  @override
  void injectMemberStdin(String s, String m, String t) {
    calls.add('inject:$s:$m:$t');
  }
  @override
  void submitMemberPending(String s, String m) {
    calls.add('submit:$s:$m');
  }
}

void main() {
  test('materialize/wake delegate to the materializer with the session id', () async {
    final spy = _Spy();
    final l = ChatCubitMemberLauncher(materializer: spy, sessionId: 'sess');

    await l.materialize('worker', const TeamMessage(id: '1', from: 'lead', to: 'worker', content: 'do X'));
    l.wake('worker', 'ding');
    l.nudgeSubmit('worker');

    expect(spy.calls, [
      'materialize:sess:worker:do X',
      'inject:sess:worker:ding',
      'submit:sess:worker',
    ]);
  });
}
