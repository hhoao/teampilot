import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/termux_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/termux/termux_setup_page.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';

import '../../support/post_frame_test_harness.dart';

class SpyTermuxCubit extends TermuxCubit {
  SpyTermuxCubit({
    required super.store,
    required super.credentials,
    required super.nativeAppDataPath,
    required super.selectHome,
    required super.testConnect,
    required this.homeSelections,
    this.onConnect,
    this.onClearSetup,
  });

  final Future<void> Function()? onConnect;
  final Future<void> Function()? onClearSetup;
  final List<String> homeSelections;

  int saveConfigCalls = 0;
  int connectCalls = 0;
  int clearSetupCalls = 0;

  @override
  Future<void> saveConfig(TermuxConfig config) async {
    saveConfigCalls++;
    await super.saveConfig(config);
  }

  @override
  Future<void> connect() async {
    connectCalls++;
    if (onConnect != null) {
      await onConnect!();
      return;
    }
    await super.connect();
  }

  @override
  Future<void> clearSetup() async {
    clearSetupCalls++;
    if (onClearSetup != null) {
      await onClearSetup!();
      return;
    }
    await super.clearSetup();
  }
}

SpyTermuxCubit _createSpyCubit(Directory nativeDir) {
  final store = TermuxConfigStore(
    rootDir: nativeDir.path,
    fs: LocalFilesystem(
      pathContext: AppPaths.pathContextForDataRoot(nativeDir.path),
    ),
  );
  final credentials = InMemorySshCredentialStore();
  final homeSelections = <String>[];
  late SpyTermuxCubit spy;
  spy = SpyTermuxCubit(
    store: store,
    credentials: credentials,
    nativeAppDataPath: nativeDir.path,
    homeSelections: homeSelections,
    selectHome: (id) async => homeSelections.add(id),
    testConnect: (_) async => (ok: true, message: ''),
    onConnect: () async {
      spy.emit(
        spy.state.copyWith(
          connected: true,
          connecting: false,
          clearLastError: true,
        ),
      );
    },
  );
  return spy;
}

void _largeTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable).first;
  await tester.drag(scrollable, const Offset(0, -1200));
  await tester.pump();
}

Future<void> _pumpSetupPage(
  WidgetTester tester, {
  required SpyTermuxCubit cubit,
  required SshCredentialStore credentials,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          return TpTheme(
            data: TpThemeData.fromColorScheme(scheme, scale: 1),
            child: MultiRepositoryProvider(
              providers: [
                RepositoryProvider<SshCredentialStore>.value(
                  value: credentials,
                ),
              ],
              child: BlocProvider<TermuxCubit>.value(
                value: cubit,
                child: const TermuxSetupPage(),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pump();
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
}

void main() {
  late Directory nativeDir;

  setUp(() async {
    setUpTestAppStorage();
    nativeDir = await Directory.systemTemp.createTemp('termux_setup_page_');
    AppPathsBootstrapper.syncPaths(AppPaths(nativeDir.path));
  });

  tearDown(() async {
    tearDownTestAppStorage();
    if (await nativeDir.exists()) {
      await nativeDir.delete(recursive: true);
    }
  });

  test('clearSetup selects local home', () async {
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    await cubit.saveConfig(const TermuxConfig(username: 'u0_a1'));
    await cubit.clearSetup();
    expect(cubit.homeSelections, contains(RuntimeTarget.localId));
    expect(cubit.state.config, isNull);
  });

  test('connect saves config and invokes cubit connect', () async {
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await cubit.saveConfig(const TermuxConfig(username: 'u0_a123'));
    await cubit.connect();

    expect(cubit.saveConfigCalls, 1);
    expect(cubit.connectCalls, 1);
    expect(cubit.state.connected, isTrue);
    expect(cubit.state.config?.username, 'u0_a123');
  });

  testWidgets('shows guided step texts and username field', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TermuxSetupPage)),
    );
    expect(find.text(l10n.termuxSetupStepInstallOpenssh), findsOneWidget);
    expect(find.text(l10n.termuxSetupStepAuthorizedKeys), findsOneWidget);
    expect(find.text(l10n.termuxSetupStepStorage), findsOneWidget);
    expect(find.text(l10n.termuxSetupStepStartSshd), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(l10n.termuxSetupStepWhoami),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(l10n.termuxSetupStepWhoami), findsOneWidget);
    expect(find.byKey(const Key('termux_username_field')), findsOneWidget);
    expect(find.text('pkg install openssh'), findsOneWidget);
    expect(find.text('termux-setup-storage'), findsOneWidget);
    expect(find.text('sshd'), findsOneWidget);
    expect(find.text('whoami'), findsOneWidget);
  });

  testWidgets('invalid username shows validation error', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TermuxSetupPage)),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('termux_username_field')),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('termux_username_field')), 'bad');
    await tester.pump();
    await _scrollToBottom(tester);
    await tester.tap(find.text(l10n.termuxSetupConnect));
    await tester.pump();

    expect(find.text(l10n.termuxSetupUsernameError), findsOneWidget);
    expect(cubit.connectCalls, 0);
  });

  testWidgets('shows connect action after valid username entry', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
    );

    await tester.enterText(
      find.byKey(const Key('termux_username_field')),
      'u0_a123',
    );
    await tester.pump();

    expect(find.text('u0_a123'), findsOneWidget);
    expect(find.byKey(const Key('termux_connect_button')), findsOneWidget);
  });

  testWidgets('Clear setup confirms and invokes clear path', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TermuxSetupPage)),
    );

    await _scrollToBottom(tester);
    await tester.tap(find.byKey(const Key('termux_clear_setup_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(l10n.termuxSetupClearConfirmTitle), findsOneWidget);
    await tester.tap(find.byKey(const Key('termux_clear_confirm_button')));
    await tester.pump();
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (cubit.clearSetupCalls > 0) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();

    expect(cubit.clearSetupCalls, 1);
    expect(cubit.state.config, isNull);
  });
}
