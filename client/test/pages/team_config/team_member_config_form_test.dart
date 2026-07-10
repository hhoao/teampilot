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
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import '../../support/stub_member_roster_service.dart';
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

Future<void> _pumpMemberForm(
  WidgetTester tester, {
  required LaunchProfileCubit launchCubit,
  Locale locale = const Locale('en'),
}) async {
  final expertHubCubit = ExpertHubCubit(
    source: CompositeExpertHubSource(
      builtIns: builtinExpertMembers(),
      registry: _EmptyRegistry(),
    ),
    loadFavorites: () async => const {},
    saveFavoriteToggle: (_) async => true,
    memberRosterService: stubMemberRosterService(),
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
      locale: locale,
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

      await _pumpMemberForm(tester, launchCubit: launchCubit);

      expect(tester.takeException(), isNull);
      expect(find.byType(TeamMemberConfigForm), findsOneWidget);
    },
  );

  testWidgets(
    'team-lead with expert shows responsibilities and empty playbook hint',
    (tester) async {
      final lead = builtinExpertMembers().firstWhere(
        (m) => m.key == 'teampilot/builtin/team-lead',
      );
      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(
          Directory.systemTemp.createTempSync('member_form_lead_'),
        ),
        sessionRepository: SessionRepository(),
        executableResolver: () => 'claude',
      );
      addTearDown(launchCubit.close);
      launchCubit.applyState(
        LaunchProfileState(
          isLoading: false,
          identities: [
            TeamProfile(
              id: 'team-1',
              name: 'Team',
              cli: CliTool.claude,
              roster: const [
                TeamRosterSlot(
                  id: TeamMemberNaming.teamLeadName,
                  expertKey: 'teampilot/builtin/team-lead',
                ),
              ],
              members: [
                TeamMemberConfig(
                  id: TeamMemberNaming.teamLeadName,
                  name: lead.name,
                  // Stale empty cache — UI must resolve from catalog expert.
                  prompt: '',
                  playbook: '',
                ),
              ],
            ),
          ],
          selectedTeamId: 'team-1',
        ),
      );

      await _pumpMemberForm(tester, launchCubit: launchCubit);

      expect(find.textContaining('Coordinate the team'), findsOneWidget);
      expect(find.text('No expert'), findsNothing);
      expect(find.text('No playbook on this expert'), findsOneWidget);
      expect(find.text('Playbook'), findsOneWidget);
    },
  );

  testWidgets(
    'zh labels use 工作手册 and empty playbook hint when expert selected',
    (tester) async {
      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(
          Directory.systemTemp.createTempSync('member_form_zh_'),
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
                  expertKey: 'teampilot/builtin/team-lead',
                ),
              ],
              members: [
                TeamMemberConfig(
                  id: TeamMemberNaming.teamLeadName,
                  name: 'Team lead',
                ),
              ],
            ),
          ],
          selectedTeamId: 'team-1',
        ),
      );

      await _pumpMemberForm(
        tester,
        launchCubit: launchCubit,
        locale: const Locale('zh'),
      );

      expect(find.text('工作手册'), findsOneWidget);
      expect(find.text('未选择专家'), findsNothing);
      expect(find.text('该专家未填写工作手册'), findsOneWidget);
    },
  );

  testWidgets(
    'member form has no save-as-template overflow menu',
    (tester) async {
      final launchCubit = LaunchProfileCubit(
        repository: testLaunchProfileRepository(
          Directory.systemTemp.createTempSync('member_form_no_save_tpl_'),
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
                  expertKey: 'teampilot/builtin/team-lead',
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

      await _pumpMemberForm(tester, launchCubit: launchCubit);

      // Save-as-template was removed; overflow must not offer it.
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.text('Save as template'), findsNothing);
    },
  );
}
