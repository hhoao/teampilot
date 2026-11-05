import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/session/chat_tab.dart';
import 'package:teampilot/services/chat/session/chat_tab_info.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/chat/team_bus/remote/remote_bus_mount.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/services/ssh/ssh_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_member_session.dart';
import 'package:teampilot/services/ssh/worker/ssh_worker_storage_types.dart';

import '../../services/chat/team_bus/support/fake_reverse_tunnel.dart';

ChatTab _tab() => ChatTab(
  info: ChatTabInfo(id: 's1', title: 's1', subtitle: ''),
  cliTeamName: 'team-a',
);

void main() {
  group('ChatTab remote plane lifecycle', () {
    test(
      'closeMemberRemotePlane only tears down the requested member mount',
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
      },
    );

    test(
      'closeMemberRemotePlane waits for the member proxy lease to close',
      () async {
        final tab = _tab();
        final transport = _CloseRecordingMemberTransport();
        tab.memberSshSessions['a'] = SshMemberSession.testing(
          profile: const SshProfile(
            id: 'p1',
            name: 'Test',
            host: 'example.test',
            username: 'tester',
          ),
          transport: transport,
        );

        await tab.closeMemberRemotePlane('a');

        expect(tab.memberSshSessions, isEmpty);
        expect(transport.closeCount, 1);
      },
    );
  });
}

final class _CloseRecordingMemberTransport implements SshWorkerMemberTransport {
  var closeCount = 0;

  @override
  Future<void> close() async {
    closeCount++;
  }

  @override
  Future<void> open(
    SshProfile profile, {
    Duration timeout = Duration.zero,
  }) async {}

  @override
  Future<SshWorkerPtyChannel> openPty({
    String? command,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) => throw UnimplementedError();

  @override
  Future<SshWorkerRunResult> run(String command, {bool stderr = true}) async =>
      SshWorkerRunResult(
        stdout: Uint8List(0),
        stderr: Uint8List(0),
        exitCode: 0,
        signalName: null,
      );

  @override
  Future<SshWorkerExecChannel> startProcess(String command) async =>
      throw UnsupportedError('not used by this test');
}
