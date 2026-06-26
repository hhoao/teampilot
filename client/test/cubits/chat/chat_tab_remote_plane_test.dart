import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_mount.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../../services/team_bus/support/fake_member_launcher.dart';
import '../../services/team_bus/support/fake_reverse_tunnel.dart';

ChatTab _tab() => ChatTab(
      info: ChatTabInfo(id: 's1', title: 's1', subtitle: ''),
      cliTeamName: 'team-a',
    );

void main() {
  group('ChatTab remote plane lifecycle', () {
    test('closeMemberRemotePlane only tears down the requested member mount',
        () async {
      final tab = _tab();
      final bus = TeamBus(launcher: FakeMemberLauncher());
      final handler = TeammateBusMcpHandler(bus: bus);
      tab.memberRemoteBusMounts['a'] = RemoteBusMount.testing(
        handler: handler,
        httpBusPort: 1,
        tunnelFactory: () => FakeReverseTunnel(port: 51001),
        storageFs: LocalFilesystem(),
        remoteRun: (cmd) async => '',
        arch: 'linux-x64',
      );
      tab.memberRemoteBusMounts['b'] = RemoteBusMount.testing(
        handler: handler,
        httpBusPort: 2,
        tunnelFactory: () => FakeReverseTunnel(port: 51002),
        storageFs: LocalFilesystem(),
        remoteRun: (cmd) async => '',
        arch: 'linux-x64',
      );

      await tab.closeMemberRemotePlane('a');

      expect(tab.memberRemoteBusMounts.containsKey('a'), isFalse);
      expect(tab.memberRemoteBusMounts.containsKey('b'), isTrue);
    });
  });
}
