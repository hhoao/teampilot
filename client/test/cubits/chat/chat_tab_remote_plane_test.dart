import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/team_bus/remote/remote_bus_mount.dart';

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
      tab.memberRemoteBusMounts['a'] = RemoteBusMount.testing(
        httpBusPort: 1,
        rawSocketPort: 2,
        tunnelFactory: () => FakeReverseTunnel(port: 51001),
        storageFs: LocalFilesystem(),
        remoteRun: (cmd) async => '',
        arch: 'linux-x64',
      );
      tab.memberRemoteBusMounts['b'] = RemoteBusMount.testing(
        httpBusPort: 3,
        rawSocketPort: 4,
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
