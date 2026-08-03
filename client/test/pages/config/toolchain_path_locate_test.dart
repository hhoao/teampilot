import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/pages/config/toolchain_path_settings_row.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../support/post_frame_test_harness.dart';

Future<SessionPreferencesCubit> _makeCubit({
  Map<String, String> locatedToolchains = const {},
}) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
    locatedToolchains: locatedToolchains,
  );
  await cubit.load();
  return cubit;
}

Widget _wrapRow(
  SessionPreferencesCubit cubit, {
  Future<String?> Function()? locateOverride,
  ConnectionModeService? connectionMode,
}) {
  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>(
        create: (_) =>
            connectionMode ??
            ConnectionModeService(
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
        home: Scaffold(
          body: ToolchainPathSettingsRow(
            cubit: cubit,
            toolId: SessionPreferences.toolchainGit,
            title: 'Git',
            subtitle: 'Path to git',
            fallbackExecutable: 'git',
            fieldKey: AppKeys.gitToolchainPathField,
            browseKey: AppKeys.gitToolchainPathBrowseButton,
            resetKey: AppKeys.gitToolchainPathResetButton,
            installKey: AppKeys.gitToolchainInstallButton,
            debouncerTag: 'git_toolchain_path_test',
            showDividerBelow: false,
            locateOverride: locateOverride,
          ),
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

  testWidgets('shows Locate when toolchain path is empty', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrapRow(cubit));
    await tester.pump();

    final button = find.byKey(AppKeys.gitToolchainPathResetButton);
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('Locate')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.text('Reset')),
      findsNothing,
    );
  });

  testWidgets('shows Reset when toolchain path is configured', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await cubit.setToolchainPath(
      SessionPreferences.toolchainGit,
      '/usr/bin/git',
    );
    await tester.pumpWidget(_wrapRow(cubit));
    await tester.pump();

    final button = find.byKey(AppKeys.gitToolchainPathResetButton);
    expect(
      find.descendant(of: button, matching: find.text('Reset')),
      findsOneWidget,
    );
  });

  testWidgets('Locate success writes and persists path', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _wrapRow(cubit, locateOverride: () async => '/usr/bin/git'),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.gitToolchainPathResetButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      cubit.toolchainPath(SessionPreferences.toolchainGit),
      '/usr/bin/git',
    );
    expect(find.text('Reset'), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('remote Locate uses override and persists path', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _wrapRow(
        cubit,
        connectionMode: ConnectionModeService(
          defaultTargetResolver: () => RuntimeTarget.ssh('p1', label: 'box'),
          hasSshProfiles: () => true,
        ),
        locateOverride: () async => '/usr/local/bin/git',
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.gitToolchainPathResetButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      cubit.toolchainPath(SessionPreferences.toolchainGit),
      '/usr/local/bin/git',
    );
    AppToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });
}
