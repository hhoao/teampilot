import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/widgets/right_tools/right_tools_tool_views.dart';

/// Records every [syncPresenceTeam] call so tests can assert that the panel
/// re-syncs its team on workspace re-activation.
class _RecordingPresenceCubit extends MemberPresenceCubit {
  final List<TeamProfile?> syncedTeams = [];

  @override
  void syncPresenceTeam(TeamProfile? team) {
    syncedTeams.add(team);
    super.syncPresenceTeam(team);
  }
}

void main() {
  const teamA = TeamProfile(
    id: 'team-a',
    name: 'A',
    members: [TeamMemberConfig(id: 'm-lead', name: 'team-lead')],
  );

  Widget host(_RecordingPresenceCubit cubit, {required bool tickerEnabled}) {
    return MaterialApp(
      home: BlocProvider<MemberPresenceCubit>.value(
        value: cubit,
        child: TickerMode(
          enabled: tickerEnabled,
          child: RightToolsPresenceTeamSync(
            team: teamA,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );
  }

  testWidgets('re-syncs the presence team when the workspace is re-activated', (
    tester,
  ) async {
    final cubit = _RecordingPresenceCubit();
    addTearDown(cubit.close);

    // First activation: the panel syncs its team once.
    await tester.pumpWidget(host(cubit, tickerEnabled: true));
    await tester.pump();
    expect(cubit.syncedTeams, [teamA]);

    // Deactivate the workspace (kept alive, TickerMode off) — no sync.
    await tester.pumpWidget(host(cubit, tickerEnabled: false));
    await tester.pump();
    expect(cubit.syncedTeams, [teamA]);

    // Re-activate with the SAME team: the cubit must be told again — another
    // workspace's panel may have synced a different team in the meantime.
    await tester.pumpWidget(host(cubit, tickerEnabled: true));
    await tester.pump();
    expect(cubit.syncedTeams, [teamA, teamA]);
  });

  testWidgets('does not re-sync while the workspace stays active', (
    tester,
  ) async {
    final cubit = _RecordingPresenceCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(host(cubit, tickerEnabled: true));
    await tester.pump();
    await tester.pumpWidget(host(cubit, tickerEnabled: true));
    await tester.pump();
    expect(cubit.syncedTeams, [teamA]);
  });
}
