import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_roster_slot.dart';
import 'package:teampilot/pages/expert_hub/expert_landing_picker_sheet.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_team_tab.dart';
import 'package:teampilot/pages/team_config/team_config_section.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/local_member_template_store.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _FakeSource extends CompositeExpertHubSource {
  _FakeSource(this.members)
    : super(
        builtIns: members,
        registry: _EmptyRegistry(),
        localStore: LocalMemberTemplateStore(
          fs: InMemoryFilesystem(),
          dirOverride: '/local-templates',
        ),
      );

  final List<DiscoverableMember> members;

  @override
  Future<List<DiscoverableMember>> fetchMembers({
    bool forceRefresh = false,
  }) async => members;
}

class _EmptyRegistry implements ExpertHubSource {
  @override
  Future<List<DiscoverableMember>> fetchMembers({bool forceRefresh = false}) =>
      Future.value(const []);

  @override
  Future<List<String>> categories({bool forceRefresh = false}) =>
      Future.value(const []);
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets(
    'HomeTeamTab add-member opens expert picker instead of adding immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final leadKey = 'teampilot/builtin/team-lead';
      final expert = builtinExpertMembers().firstWhere(
        (m) => m.key == 'teampilot/builtin/reviewer',
      );

      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        cli: CliTool.claude,
        roster: [
          TeamRosterSlot(
            id: TeamMemberNaming.teamLeadName,
            expertKey: leadKey,
          ),
        ],
        members: [
          TeamMemberConfig(
            id: TeamMemberNaming.teamLeadName,
            name: 'Lead',
          ),
        ],
      );

      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(
          Directory.systemTemp.createTempSync('home_team_add_member_'),
        ),
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
      );
      addTearDown(launchCubit.close);
      launchCubit.applyState(
        LaunchProfileState(
          isLoading: false,
          identities: [team],
          selectedTeamId: team.id,
        ),
      );

      final expertHubCubit = ExpertHubCubit(
        source: _FakeSource([expert]),
        loadFavorites: () async => const {},
        saveFavoriteToggle: (_) async => true,
        memberRosterService: MemberRosterService(
          installSkill: (_) async => null,
        ),
        launchProfiles: () => launchCubit,
      );
      addTearDown(expertHubCubit.close);
      await expertHubCubit.load();

      final cliPresetsCubit = CliPresetsCubit(
        repository: CliPresetsRepository(
          fs: InMemoryFilesystem(),
          presetsPath: '/cli-presets.json',
        ),
      );
      addTearDown(cliPresetsCubit.close);

      final providerCubit = AppProviderCubit();
      addTearDown(providerCubit.close);

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: launchCubit),
            BlocProvider.value(value: expertHubCubit),
            BlocProvider.value(value: cliPresetsCubit),
            BlocProvider.value(value: providerCubit),
          ],
          child: CliToolRegistryScope(
            registry: CliToolRegistry.builtIn(),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: HomeTeamTab(
                  team: team,
                  section: TeamConfigSection.members,
                  cubit: launchCubit,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.person_add_alt_1_outlined), findsOneWidget);
      expect(launchCubit.state.selectedTeam!.members, hasLength(1));

      await tester.tap(find.byIcon(Icons.person_add_alt_1_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExpertLandingPickerSheet), findsOneWidget);
      expect(launchCubit.state.selectedTeam!.members, hasLength(1));

      await tester.tap(find.text(expert.name));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ExpertLandingPickerSheet), findsNothing);
      expect(launchCubit.state.selectedTeam!.members, hasLength(2));
      expect(
        launchCubit.state.selectedTeam!.roster.last.expertKey,
        expert.key,
      );
    },
  );
}
