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
import 'package:teampilot/pages/team_config/team_config_member_section.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/member_roster_service.dart';
import 'package:teampilot/utils/team_member_naming.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

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
    'TeamMemberConfigForm builds without nested context.read in select',
    (tester) async {
      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(
          Directory.systemTemp.createTempSync('member_form_'),
        ),
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
      );
      addTearDown(launchCubit.close);
      launchCubit.applyState(
        const LaunchProfileState(
          isLoading: false,
          identities: [
            TeamProfile(
              id: 'team-1',
              name: 'Team',
              cli: CliTool.claude,
              roster: [
                TeamRosterSlot(
                  id: TeamMemberNaming.teamLeadName,
                  expertKey: '',
                ),
              ],
              members: [
                TeamMemberConfig(
                  id: TeamMemberNaming.teamLeadName,
                  name: 'Lead',
                ),
              ],
            ),
          ],
          selectedTeamId: 'team-1',
        ),
      );

      final expertHubCubit = ExpertHubCubit(
        source: CompositeExpertHubSource(
          builtIns: const [],
          registry: _EmptyRegistry(),
        ),
        loadFavorites: () async => const {},
        saveFavoriteToggle: (_) async => true,
        memberRosterService: MemberRosterService(
          installSkill: (_) async => null,
        ),
        launchProfiles: () => launchCubit,
      );
      addTearDown(expertHubCubit.close);

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
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: launchCubit),
              BlocProvider.value(value: expertHubCubit),
              BlocProvider.value(value: cliPresetsCubit),
              BlocProvider.value(value: providerCubit),
            ],
            child: CliToolRegistryScope(
              registry: CliToolRegistry.builtIn(),
              child: const Scaffold(
                body: SingleChildScrollView(
                  child: TeamMemberConfigForm(
                    teamId: 'team-1',
                    memberId: TeamMemberNaming.teamLeadName,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(TeamMemberConfigForm), findsOneWidget);
    },
  );
}
