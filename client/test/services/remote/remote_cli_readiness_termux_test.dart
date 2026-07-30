import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/remote/remote_cli_readiness.dart';
import 'package:teampilot/services/ssh/ssh_client_factory.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_transport_profile.dart';

void main() {
  group('RemoteCliReadinessService termux', () {
    late List<String> profileLookups;

    RemoteCliReadinessService buildService() {
      profileLookups = [];
      return RemoteCliReadinessService(
        registry: CliToolRegistry.builtIn(),
        sshClientFactory: _ThrowingSshClientFactory(),
        profileById: (id) {
          profileLookups.add(id);
          if (id == 'termux') {
            return termuxTransportProfile(
              const TermuxConfig(
                username: 'u0_a123',
                host: '127.0.0.1',
                port: 8022,
              ),
            );
          }
          return null;
        },
        cliPathOverride: (_, __) async => null,
        setCliPathOverride: (_, __, ___) async {},
      );
    }

    test('probe rejects local target', () async {
      final service = buildService();
      await expectLater(
        service.probe(target: RuntimeTarget.local(), cli: CliTool.claude),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('probe accepts termux target and resolves synthetic profile', () async {
      final service = buildService();
      final result = await service.probe(
        target: RuntimeTarget.termux(),
        cli: CliTool.claude,
      );
      expect(profileLookups, ['termux']);
      expect(result.targetId, RuntimeTarget.termuxDefaultId);
      expect(result.cli, CliTool.claude);
      expect(result, isA<RemoteCliFailed>());
    });
  });

  group('profileByIdIncludingTermux', () {
    test('returns synthetic profile when termux config exists', () {
      const config = TermuxConfig(
        username: 'u0_a123',
        host: '127.0.0.1',
        port: 8022,
      );
      final profile = profileByIdIncludingTermux(
        id: 'termux',
        termuxConfig: config,
        catalogProfileById: (_) => null,
      );
      expect(profile, isNotNull);
      expect(profile!.id, 'termux');
    });

    test('returns null when termux config missing', () {
      final profile = profileByIdIncludingTermux(
        id: 'termux',
        termuxConfig: null,
        catalogProfileById: (_) => null,
      );
      expect(profile, isNull);
    });
  });
}

class _ThrowingSshClientFactory implements SshClientFactory {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
