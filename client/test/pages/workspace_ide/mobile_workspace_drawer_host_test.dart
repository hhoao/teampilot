import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/workspace_ide/mobile_workspace_drawer_host.dart';
import 'package:teampilot/widgets/notification/notification_bell_button.dart';

import '../../support/post_frame_test_harness.dart';

class _HostHarness extends StatefulWidget {
  const _HostHarness({
    required this.open,
    required this.initialMode,
    super.key,
  });

  final bool open;
  final MobileDrawerMode initialMode;

  @override
  State<_HostHarness> createState() => _HostHarnessState();
}

class _HostHarnessState extends State<_HostHarness> {
  late MobileDrawerMode _mode;
  final modeChanges = <MobileDrawerMode>[];
  var dismissCount = 0;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
  }

  @override
  Widget build(BuildContext context) {
    return MobileWorkspaceDrawerHost(
      open: widget.open,
      mode: _mode,
      width: 280,
      chatBody: const Text('CHAT_BODY'),
      toolsBody: const Text('TOOLS_BODY'),
      onDismiss: () => dismissCount++,
      onModeChanged: (mode) {
        modeChanges.add(mode);
        setState(() => _mode = mode);
      },
      onOpenWorkspaceManagement: () {},
      child: const Text('CENTER'),
    );
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<_HostHarnessState> pumpHarness(
    WidgetTester tester, {
    bool open = true,
    MobileDrawerMode initialMode = MobileDrawerMode.chat,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeData(useMaterial3: true);
    final harnessKey = GlobalKey<_HostHarnessState>();

    await tester.pumpWidget(
      TpTheme(
        data: TpThemeData.fromColorScheme(
          theme.colorScheme,
          scale: 1.0,
        ),
        child: MultiBlocProvider(
          providers: [
            BlocProvider(create: (_) => LayoutCubit()),
            BlocProvider(create: (_) => NotificationCubit()),
            BlocProvider(
              create: (context) => ProgressActivityCubit(
                historyRecorder: context.read<NotificationCubit>(),
              ),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            home: Scaffold(
              body: _HostHarness(
                key: harnessKey,
                open: open,
                initialMode: initialMode,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harnessKey.currentState!;
  }

  testWidgets('open chat mode shows chat body and shared footer', (
    tester,
  ) async {
    await pumpHarness(tester);

    expect(find.text('CHAT_BODY'), findsOneWidget);
    expect(find.text('TOOLS_BODY'), findsNothing);
    expect(find.text('Workspace management'), findsOneWidget);
    expect(find.byType(NotificationBellButton), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
  });

  testWidgets('tools segment swaps body while footer stays visible', (
    tester,
  ) async {
    final state = await pumpHarness(tester);

    await tester.tap(find.text('Tools'));
    await tester.pumpAndSettle();

    expect(state.modeChanges, [MobileDrawerMode.tools]);
    expect(find.text('TOOLS_BODY'), findsOneWidget);
    expect(find.text('CHAT_BODY'), findsNothing);
    expect(find.text('Workspace management'), findsOneWidget);
    expect(find.byType(NotificationBellButton), findsOneWidget);
  });

  testWidgets('scrim tap dismisses drawer', (tester) async {
    final state = await pumpHarness(tester);

    // Tap the scrim on the right of the drawer panel (280px wide on 400px screen).
    await tester.tapAt(const Offset(350, 400));
    await tester.pumpAndSettle();

    expect(state.dismissCount, 1);
  });
}
