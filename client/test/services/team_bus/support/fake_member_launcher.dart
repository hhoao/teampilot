import 'package:teampilot/services/team_bus/member_launcher.dart';
import 'package:teampilot/services/team_bus/team_message.dart';

/// 手写 fake（仓库无 mock 库）：记录调用以供断言。
class FakeMemberLauncher implements MemberLauncher {
  final List<({String memberId, TeamMessage bootstrap})> materialized = [];
  final List<({String memberId, String notice})> woken = [];

  @override
  Future<void> materialize(String memberId, TeamMessage bootstrap) async {
    materialized.add((memberId: memberId, bootstrap: bootstrap));
  }

  @override
  void wake(String memberId, String notice) {
    woken.add((memberId: memberId, notice: notice));
  }
}
