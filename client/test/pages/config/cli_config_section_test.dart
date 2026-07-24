import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/config/cli_config_section.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/post_frame_test_harness.dart';

Future<SessionPreferencesCubit> _makeCubit({
  Map<CliTool, String> locatedExecutables = const {},
  Map<String, String> locatedToolchains = const {},
}) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
    locatedExecutables: locatedExecutables,
    locatedToolchains: locatedToolchains,
  );
  await cubit.load();
  return cubit;
}

Widget _wrap(SessionPreferencesCubit cubit) {
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>(
        create: (_) => ConnectionModeService(
          defaultTargetResolver: RuntimeTarget.local,
          hasSshProfiles: () => false,
        ),
      ),
    ],
    child: BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CliConfigWorkspace(showHeading: false),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(tearDownTestAppStorage);

  testWidgets('shows install button when CLI path is unknown', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.opencodeCliInstallButton), findsOneWidget);
  });

  testWidgets('hides install button when CLI path is already known', (
    tester,
  ) async {
    final cubit = await _makeCubit(
      locatedExecutables: const {
        CliTool.claude: '/usr/local/bin/claude',
        CliTool.codex: '/usr/local/bin/codex',
        CliTool.opencode: '/usr/local/bin/opencode',
        CliTool.cursor: '/usr/local/bin/cursor-agent',
      },
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.opencodeCliInstallButton), findsNothing);
  });

  testWidgets('hides toolchain install buttons when paths are known', (
    tester,
  ) async {
    final cubit = await _makeCubit(
      locatedToolchains: const {
        SessionPreferences.toolchainGit: '/usr/bin/git',
        SessionPreferences.toolchainNode: '/usr/bin/node',
      },
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.gitToolchainInstallButton), findsNothing);
    expect(find.byKey(AppKeys.nodeToolchainInstallButton), findsNothing);
  });
}
