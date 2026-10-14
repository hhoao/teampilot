import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/cli/cli_local_discovery_bootstrap.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<SessionPreferencesCubit> makeCubit({
    Map<CliTool, String> locatedExecutables = const {},
    Map<String, String> locatedToolchains = const {},
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return SessionPreferencesCubit(
      repository: SessionPreferencesRepository(prefs),
      locatedExecutables: locatedExecutables,
      locatedToolchains: locatedToolchains,
    );
  }

  test('runLocalCliDiscovery merges CLI, adapter, toolchain, then versions', () async {
    final cubit = await makeCubit();
    await cubit.load();
    await runLocalCliDiscovery(
      cubit: cubit,
      locateCli: () async => {CliTool.claude: '/bin/claude'},
      locateAdapters: () async => {CliTool.claude: '/bin/claude-agent-acp'},
      locateToolchains: () async => {'git': '/usr/bin/git'},
      probeInstalled: (path) async => switch (path) {
        '/bin/claude' => '2.1.4',
        '/bin/claude-agent-acp' => '0.12.1',
        _ => null,
      },
    );
    expect(cubit.discoveredExecutablePath(CliTool.claude), '/bin/claude');
    expect(cubit.discoveredAcpAdapterPath(CliTool.claude), '/bin/claude-agent-acp');
    expect(cubit.installedVersion(CliTool.claude, CliBinaryKind.cli), '2.1.4');
    expect(
      cubit.installedVersion(CliTool.claude, CliBinaryKind.adapter),
      '0.12.1',
    );
  });
}
