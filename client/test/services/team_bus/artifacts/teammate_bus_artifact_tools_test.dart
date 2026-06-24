import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_registry.dart';
import 'package:teampilot/services/team_bus/artifacts/artifact_transfer_service.dart';
import 'package:teampilot/services/team_bus/mcp/jsonrpc.dart';
import 'package:teampilot/services/team_bus/mcp/teammate_bus_mcp_handler.dart';
import 'package:teampilot/services/team_bus/team_bus.dart';

import '../../../support/in_memory_filesystem.dart';
import '../support/fake_member_launcher.dart';

class _Harness {
  _Harness({bool withArtifacts = true}) {
    final service = withArtifacts
        ? ArtifactTransferService(
            registry: ArtifactRegistry(),
            resolveFs: (targetId) async => _fsByTarget[targetId]!,
            targetForMember: (memberId) => _targetByMember[memberId]!,
            inboxDirFor: (memberId) => _inboxByMember[memberId]!,
          )
        : null;
    handler = TeammateBusMcpHandler(
      bus: TeamBus(launcher: FakeMemberLauncher()),
      artifacts: service,
    );
  }

  final InMemoryFilesystem publisherFs = InMemoryFilesystem();
  final InMemoryFilesystem fetcherFs = InMemoryFilesystem();
  late final Map<String, Filesystem> _fsByTarget = {
    'local': publisherFs,
    'ssh:hostB': fetcherFs,
  };
  final Map<String, String> _targetByMember = {
    'A': 'local',
    'B': 'ssh:hostB',
  };
  final Map<String, String> _inboxByMember = {
    'A': '/home/a/inbox',
    'B': '/remote/inbox',
  };

  late final TeammateBusMcpHandler handler;
}

Future<String> _callText(
  TeammateBusMcpHandler handler,
  String memberId,
  String tool,
  Map<String, Object?> args,
) async {
  final res = await handler.handle(
    memberId,
    JsonRpcRequest(id: 1, method: 'tools/call', params: {
      'name': tool,
      'arguments': args,
    }),
  );
  return (res!.result!['content'] as List).first['text'] as String;
}

Future<bool> _callIsError(
  TeammateBusMcpHandler handler,
  String memberId,
  String tool,
  Map<String, Object?> args,
) async {
  final res = await handler.handle(
    memberId,
    JsonRpcRequest(id: 1, method: 'tools/call', params: {
      'name': tool,
      'arguments': args,
    }),
  );
  return res!.result!['isError'] as bool;
}

void main() {
  group('teammate-bus artifact tools', () {
    test('tools/list advertises artifact tools only when service injected',
        () async {
      final with_ = _Harness();
      final res = await with_.handler
          .handle('A', const JsonRpcRequest(id: 1, method: 'tools/list'));
      final names = [
        for (final t in res!.result!['tools'] as List) (t as Map)['name'],
      ];
      expect(names,
          containsAll(['publish_artifact', 'list_artifacts', 'fetch_artifact']));

      final without = _Harness(withArtifacts: false);
      final res2 = await without.handler
          .handle('A', const JsonRpcRequest(id: 1, method: 'tools/list'));
      final names2 = [
        for (final t in res2!.result!['tools'] as List) (t as Map)['name'],
      ];
      expect(names2, isNot(contains('publish_artifact')));
      expect(names2, isNot(contains('list_artifacts')));
      expect(names2, isNot(contains('fetch_artifact')));
    });

    test('publish → list → fetch round trip dispatches expected text',
        () async {
      final h = _Harness();
      await h.publisherFs
          .writeBytes('/work/out.bin', List<int>.generate(16, (i) => i));

      final publish = await _callText(
        h.handler, 'A', 'publish_artifact', {
          'path': '/work/out.bin',
          'name': 'out',
        },
      );
      expect(publish, contains('Published "out"'));

      final list = await _callText(h.handler, 'B', 'list_artifacts', {});
      expect(list, contains('out'));
      expect(list, contains('by A'));

      final fetch = await _callText(
        h.handler, 'B', 'fetch_artifact', {
          'name': 'out',
          'destPath': 'got.bin',
        },
      );
      expect(fetch, contains('Fetched "out"'));
      expect(fetch, contains('/remote/inbox/got.bin'));
      expect(
        await h.fetcherFs.readBytes('/remote/inbox/got.bin'),
        List<int>.generate(16, (i) => i),
      );
    });

    test('fetch of an unknown artifact is a tool error', () async {
      final h = _Harness();
      final isError = await _callIsError(
        h.handler, 'B', 'fetch_artifact', {
          'name': 'ghost',
          'destPath': 'x.bin',
        },
      );
      expect(isError, isTrue);
    });

    test('publish with a missing path/name is a tool error', () async {
      final h = _Harness();
      final isError = await _callIsError(
        h.handler, 'A', 'publish_artifact', {'path': '', 'name': 'out'},
      );
      expect(isError, isTrue);
    });

    test('publish with an unsupported kind is a tool error', () async {
      final h = _Harness();
      await h.publisherFs.writeBytes('/work/out.bin', [1]);
      final isError = await _callIsError(
        h.handler, 'A', 'publish_artifact', {
          'path': '/work/out.bin',
          'name': 'out',
          'kind': 'dir',
        },
      );
      expect(isError, isTrue);
    });
  });
}
