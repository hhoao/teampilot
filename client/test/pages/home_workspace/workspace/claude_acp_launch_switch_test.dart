import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/claude_acp_launch_switch.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

class _MockSessionPreferencesCubit extends Mock
    implements SessionPreferencesCubit {}

void main() {
  Future<_MockSessionPreferencesCubit> pumpSwitch(
    WidgetTester tester, {
    required CliTool? cli,
    bool isPersonal = true,
    bool isAndroid = false,
    bool preferenceDefault = false,
    bool? override,
    ValueChanged<bool>? onChanged,
  }) async {
    final cubit = _MockSessionPreferencesCubit();
    final state = SessionPreferencesState(
      preferences: SessionPreferences(
        claudePersonalAcpDefault: preferenceDefault,
      ),
    );
    when(() => cubit.state).thenReturn(state);
    when(() => cubit.stream).thenAnswer((_) => const Stream.empty());
    await tester.pumpWidget(
      BlocProvider<SessionPreferencesCubit>.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ClaudeAcpLaunchSwitch(
              cli: cli,
              isPersonal: isPersonal,
              localOverride: override,
              onChanged: onChanged ?? (_) {},
              isAndroidOverride: isAndroid,
            ),
          ),
        ),
      ),
    );
    return cubit;
  }

  bool switchValue(WidgetTester tester) => tester
      .widget<SwitchListTile>(find.byKey(AppKeys.claudeAcpLaunchSwitch))
      .value;

  group('ClaudeAcpLaunchSwitch', () {
    testWidgets('shows for personal Claude on desktop', (tester) async {
      await pumpSwitch(tester, cli: CliTool.claude);
      expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsOneWidget);
    });

    testWidgets('hidden for non-Claude CLIs', (tester) async {
      await pumpSwitch(tester, cli: CliTool.codex);
      expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsNothing);
    });

    testWidgets('hidden when no CLI is selected', (tester) async {
      await pumpSwitch(tester, cli: null);
      expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsNothing);
    });

    testWidgets('hidden for team launches', (tester) async {
      await pumpSwitch(tester, cli: CliTool.claude, isPersonal: false);
      expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsNothing);
    });

    testWidgets('hidden on Android', (tester) async {
      await pumpSwitch(tester, cli: CliTool.claude, isAndroid: true);
      expect(find.byKey(AppKeys.claudeAcpLaunchSwitch), findsNothing);
    });

    testWidgets('initializes from the settings default', (tester) async {
      await pumpSwitch(tester, cli: CliTool.claude, preferenceDefault: true);
      expect(switchValue(tester), isTrue);
    });

    testWidgets('local override wins over the settings default', (
      tester,
    ) async {
      await pumpSwitch(
        tester,
        cli: CliTool.claude,
        preferenceDefault: true,
        override: false,
      );
      expect(switchValue(tester), isFalse);
    });

    testWidgets('flipping reports the new value and never writes the pref', (
      tester,
    ) async {
      final changes = <bool>[];
      final cubit = await pumpSwitch(
        tester,
        cli: CliTool.claude,
        onChanged: changes.add,
      );
      await tester.tap(find.byKey(AppKeys.claudeAcpLaunchSwitch));
      await tester.pump();
      expect(changes, [true]);
      verifyNever(() => cubit.setClaudePersonalAcpDefault(any()));
    });
  });

  group('resolveLaunchAcp', () {
    test('true only for personal Claude when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false for team, non-Claude, not requested, or Android', () {
      bool resolve({
        bool isPersonal = true,
        CliTool? cli = CliTool.claude,
        bool requested = true,
        bool isAndroid = false,
      }) => resolveLaunchAcp(
        isPersonal: isPersonal,
        cli: cli,
        requested: requested,
        isAndroidOverride: isAndroid,
      );
      expect(resolve(isPersonal: false), isFalse);
      expect(resolve(cli: CliTool.gemini), isFalse);
      expect(resolve(cli: null), isFalse);
      expect(resolve(requested: false), isFalse);
      expect(resolve(isAndroid: true), isFalse);
    });
  });

  group('buildWorkspaceConversationCreateRequest', () {
    final workspace = Workspace(workspaceId: 'ws', createdAt: 1);

    test('personal Claude with the switch on sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
    });

    test('defaults to acp false', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('team create stays false even when acp is requested', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('Android forces acp false', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: true,
      );
      expect(request.acp, isFalse);
    });
  });
}
