import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/team_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/team_hub/team_landing_picker_sheet.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/team/team_clone_service.dart';
import 'package:teampilot/services/team_hub/team_hub_source.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeSource implements TeamHubSource {
  _FakeSource(this.teams);
  final List<DiscoverableTeam> teams;

  @override
  Future<List<DiscoverableTeam>> fetchTeams({bool forceRefresh = false}) async =>
      teams;

  @override
  Future<List<String>> categories({bool forceRefresh = false}) async =>
      teams.map((t) => t.category).toSet().toList()..sort();
}

DiscoverableTeam _hubTeam() => const DiscoverableTeam(
  key: 'o/r/s',
  name: 'Squad',
  description: 'd',
  category: 'AI',
  updatedAt: 1,
);

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<TeamHubCubit> pumpCubit() async {
    final cubit = TeamHubCubit(
      source: _FakeSource([_hubTeam()]),
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      cloneTeam: (team, {teamMode, cli}) async {
        return CloneResult(
          teamId: 'cloned-${team.key}',
          installed: const CloneDepInstallSummary(),
          failedDeps: const [],
        );
      },
    );
    await cubit.load();
    return cubit;
  }

  LaunchProfileCubit pumpLaunch() {
    final dir = Directory.systemTemp.createTempSync('team-picker-');
    addTearDown(() {
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException catch (_) {}
    });
    return LaunchProfileCubit(
      repository: testLaunchProfileRepository(dir),
      sessionRepository: SessionRepository(),
      executableResolver: () => 'claude',
    );
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required TeamHubCubit cubit,
    required LaunchProfileCubit launch,
    required Widget home,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      CliToolRegistryScope(
        registry: CliToolRegistry.builtIn(),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: cubit),
            BlocProvider.value(value: launch),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('confirm on undeclared team shows clone-options dialog first',
      (tester) async {
    final cubit = await pumpCubit();
    addTearDown(cubit.close);
    final launch = pumpLaunch();
    addTearDown(launch.close);

    String? pickedTeamId;
    await pumpHost(
      tester,
      cubit: cubit,
      launch: launch,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            pickedTeamId = await showTeamLandingPickerSheet(context);
          },
          child: const Text('open'),
        ),
      ),
    );

    // 注：此对话框栈存在一个持续 ticker（非 spinner，真机无害），pumpAndSettle
    // 永不结束，故用有界 pump 推进路由/对话框动画。
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 600));
    // 进 catalog，点 Squad 卡片 → 详情
    expect(find.text('Squad'), findsOneWidget,
        reason: 'catalog should list the hub team');

    await tester.tap(find.text('Squad'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Confirm'), findsOneWidget,
        reason: 'detail overlay should show Confirm');

    // 详情里点 Confirm → 应弹克隆选项对话框（teamMode 未声明）
    await tester.tap(find.text('Confirm'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('Clone options'), findsOneWidget);

    // 取消 → 不克隆，picker 保持打开，pickedTeamId 为 null
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 600));
    expect(pickedTeamId, isNull);
  });
}
