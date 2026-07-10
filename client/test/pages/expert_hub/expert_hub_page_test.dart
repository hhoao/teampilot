import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/expert_hub/expert_hub_page.dart';
import 'package:teampilot/services/expert_hub/composite_expert_hub_source.dart';
import 'package:teampilot/services/expert_hub/expert_hub_source.dart';
import '../../support/stub_member_roster_service.dart';

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
  testWidgets('ExpertHubPage mounts under GoRouter without initState inherit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final cubit = ExpertHubCubit(
      source: _FakeSource([_member('Alpha')]),
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      memberRosterService: stubMemberRosterService(),
      launchProfiles: () => throw UnimplementedError('not used'),
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => BlocProvider(
                create: (_) => LayoutCubit(),
                child: BlocProvider.value(
                  value: cubit,
                  child: const Scaffold(body: ExpertHubPage()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ExpertHubPage), findsOneWidget);
  });
}
