import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/termux_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/pages/termux/termux_setup_page.dart';
import 'package:teampilot/repositories/ssh_credential_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/remote_download/remote_download_catalog.dart';
import 'package:teampilot/services/remote_download/remote_download_http.dart';
import 'package:teampilot/services/remote_download/remote_download_resolver.dart';
import 'package:teampilot/services/remote_download/remote_downloader.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/termux/termux_apk_acquisition.dart';
import 'package:teampilot/services/termux/termux_config.dart';
import 'package:teampilot/services/termux/termux_config_store.dart';
import 'package:teampilot/services/termux/termux_package_probe.dart';

import '../../support/post_frame_test_harness.dart';

const _termuxReleaseJson = {
  'tag_name': 'v0.118.1',
  'assets': [
    {
      'name': 'termux-app_v0.118.1+github-debug_arm64-v8a-debug_signed.apk',
      'browser_download_url':
          'https://github.com/termux/termux-app/releases/download/v0.118.1/termux-app_v0.118.1+github-debug_arm64-v8a-debug_signed.apk',
      'size': 128,
    },
  ],
};

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
    this.fastSaveConfig = false,
  });

  final Future<void> Function()? onConnect;
  final Future<void> Function()? onClearSetup;
  final List<String> homeSelections;
  final bool fastSaveConfig;

  int saveConfigCalls = 0;
  int connectCalls = 0;
  int clearSetupCalls = 0;

  @override
  Future<void> saveConfig(TermuxConfig config) async {
    saveConfigCalls++;
    if (fastSaveConfig) {
      emit(state.copyWith(config: config, clearLastError: true));
      return;
    }
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

SpyTermuxCubit _createSpyCubit(Directory nativeDir, {bool fastSaveConfig = false}) {
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
    fastSaveConfig: fastSaveConfig,
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
  tester.view.physicalSize = const Size(1600, 10000);
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
  TermuxPackageProbe? packageProbe,
  TermuxApkAcquisition? apkAcquisition,
  bool embedded = false,
  VoidCallback? onHomeBound,
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
                child: TermuxSetupPage(
                  packageProbe: packageProbe,
                  apkAcquisition: apkAcquisition,
                  embedded: embedded,
                  onHomeBound: onHomeBound,
                ),
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

TermuxPackageProbe _notInstalledProbe() {
  const channel = MethodChannel('com.hhoa.teampilot/packages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'isPackageInstalled') return false;
    return null;
  });
  return TermuxPackageProbe(channel: channel, isAndroid: true);
}

TermuxPackageProbe _installedProbe() {
  const channel = MethodChannel('com.hhoa.teampilot/packages');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'isPackageInstalled') return true;
    return null;
  });
  return TermuxPackageProbe(channel: channel, isAndroid: true);
}

TermuxApkAcquisition _spyApkAcquisition({required void Function() onInstall}) {
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/releases/latest')) {
      return http.Response(jsonEncode(_termuxReleaseJson), 200);
    }
    return http.Response.bytes(List<int>.generate(128, (i) => i % 256), 200);
  });
  final resolver = RemoteDownloadResolver(RemoteDownloadCatalog.defaults());
  final downloadHttp = RemoteDownloadHttp(client: client, resolver: resolver);
  final downloader = RemoteDownloader(client: client, resolver: resolver);
  return TermuxApkAcquisition(
    http: downloadHttp,
    downloader: downloader,
    installApk: (_) async {
      onInstall();
      return 0;
    },
  );
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

  testWidgets('missing package shows download button and triggers acquisition',
      (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    var installTriggered = false;
    final acquisition = _spyApkAcquisition(
      onInstall: () => installTriggered = true,
    );

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
      packageProbe: _notInstalledProbe(),
      apkAcquisition: acquisition,
    );

    final l10n = AppLocalizations.of(
      tester.element(find.byType(TermuxSetupPage)),
    );

    expect(find.byKey(const Key('termux_download_install_button')), findsOneWidget);
    expect(find.text(l10n.termuxSetupDownloadInstall), findsOneWidget);
    expect(find.text(l10n.termuxSetupTermuxInstalled), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('termux_download_install_button')));
      await tester.pump();
      for (var i = 0; i < 120; i++) {
        if (installTriggered) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pump();

    expect(installTriggered, isTrue);
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

  testWidgets('Connect taps cubit saveConfig and connect', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir, fastSaveConfig: true);
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
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('termux_username_field')))
          .controller
          ?.text,
      'u0_a123',
    );

    await _scrollToBottom(tester);
    final connectButton = find.byKey(const Key('termux_connect_button'));
    await tester.ensureVisible(connectButton);
    await tester.tap(connectButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(cubit.saveConfigCalls, 1);
    expect(cubit.connectCalls, 1);
    expect(cubit.state.connected, isTrue);
    expect(cubit.state.config?.username, 'u0_a123');
    await tester.pump(const Duration(seconds: 3));
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

  testWidgets('embedded setup has no AppBar', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });

    await _pumpSetupPage(
      tester,
      cubit: cubit,
      credentials: InMemorySshCredentialStore(),
      packageProbe: _installedProbe(),
      embedded: true,
    );

    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const Key('termux_username_field')), findsOneWidget);
  });

  testWidgets('embedded connect does not pop navigator', (tester) async {
    _largeTestSurface(tester);
    final cubit = _createSpyCubit(nativeDir, fastSaveConfig: true);
    addTearDown(() async {
      if (!cubit.isClosed) await cubit.close();
    });
    var homeBoundCalls = 0;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return TpTheme(
              data: TpThemeData.fromColorScheme(scheme, scale: 1),
              child: Navigator(
                key: navigatorKey,
                initialRoute: '/',
                onGenerateRoute: (settings) {
                  switch (settings.name) {
                    case '/':
                      return MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Center(child: Text('ROOT_MARKER')),
                        ),
                      );
                    case '/setup':
                      return MaterialPageRoute<void>(
                        builder: (_) => MultiRepositoryProvider(
                          providers: [
                            RepositoryProvider<SshCredentialStore>.value(
                              value: InMemorySshCredentialStore(),
                            ),
                          ],
                          child: BlocProvider<TermuxCubit>.value(
                            value: cubit,
                            child: TermuxSetupPage(
                              packageProbe: _installedProbe(),
                              embedded: true,
                              onHomeBound: () => homeBoundCalls++,
                            ),
                          ),
                        ),
                      );
                    default:
                      return MaterialPageRoute<void>(
                        builder: (_) => const SizedBox.shrink(),
                      );
                  }
                },
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

    navigatorKey.currentState!.pushNamed('/setup');
    await tester.pump();
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
    }

    expect(find.text('ROOT_MARKER'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('termux_username_field')),
      'u0_a123',
    );
    await tester.pump();
    await _scrollToBottom(tester);
    await tester.tap(find.byKey(const Key('termux_connect_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(homeBoundCalls, 1);
    expect(find.text('ROOT_MARKER'), findsNothing);
    expect(find.byType(TermuxSetupPage), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
