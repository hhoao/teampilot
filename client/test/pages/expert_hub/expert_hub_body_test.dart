import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/expert_hub/expert_hub_body.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import '../../support/stub_member_roster_service.dart';
import 'package:teampilot/widgets/empty_state_block.dart';

class _FakeSource extends CompositeExpertHubSource {
  _FakeSource(this.members)
    : super(builtIns: members, registry: _EmptyRegistry());

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

DiscoverableMember _member(String name) => DiscoverableMember(
  key: 'o/r/${name.toLowerCase()}',
  name: name,
  description: 'desc',
  category: 'AI',
  source: ExpertMemberSource.registry,
  member: DiscoverableTeamMember(name: name.toLowerCase(), prompt: 'p'),
);

void main() {
  testWidgets('empty favorites shows EmptyStateBlock', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cubit = ExpertHubCubit(
      source: _FakeSource([_member('Alpha'), _member('Beta')]),
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      memberRosterService: stubMemberRosterService(),
      launchProfiles: () => throw UnimplementedError('not used'),
    );
    await cubit.load();
    cubit.setFavoritesOnly(true);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ExpertHubBody(
            cubit: cubit,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmptyStateBlock), findsOneWidget);
    expect(find.text('No favorites yet'), findsOneWidget);
  });
}
