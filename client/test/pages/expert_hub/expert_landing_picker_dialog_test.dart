import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/expert_hub_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/discoverable_member.dart';
import 'package:teampilot/models/discoverable_team.dart';
import 'package:teampilot/pages/expert_hub/expert_hub_cards.dart';
import 'package:teampilot/pages/expert_hub/expert_landing_picker_sheet.dart';
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
  description: 'desc for $name',
  category: 'AI',
  source: ExpertMemberSource.registry,
  member: DiscoverableTeamMember(
    name: name.toLowerCase(),
    responsibilities: 'prompt',
  ),
);

void main() {
  Future<ExpertHubCubit> pumpCubit(List<DiscoverableMember> members) async {
    final cubit = ExpertHubCubit(
      source: _FakeSource(members),
      loadFavorites: () async => const {},
      saveFavoriteToggle: (_) async => true,
      memberRosterService: stubMemberRosterService(),
      launchProfiles: () => throw UnimplementedError('not used'),
    );
    await cubit.load();
    return cubit;
  }

  Future<void> pumpHost(
    WidgetTester tester, {
    required ExpertHubCubit cubit,
    required Widget home,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('confirm returns selected expert key', (tester) async {
    final member = _member('Alpha');
    final cubit = await pumpCubit([member]);
    addTearDown(cubit.close);

    String? result;
    await pumpHost(
      tester,
      cubit: cubit,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showExpertLandingPickerSheet(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpertLandingPickerDialog), findsOneWidget);
    expect(find.text('Confirm'), findsNothing);

    await tester.tap(find.byType(ExpertHubCard));
    await tester.pumpAndSettle();

    expect(find.text('Confirm'), findsOneWidget);
    expect(result, isNull);

    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.byType(ExpertLandingPickerDialog), findsNothing);
    expect(result, member.key);
  });

  testWidgets('tapping card alone does not complete selection', (tester) async {
    final member = _member('Beta');
    final cubit = await pumpCubit([member]);
    addTearDown(cubit.close);

    var completed = false;
    await pumpHost(
      tester,
      cubit: cubit,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final key = await showExpertLandingPickerSheet(context);
              if (key != null) completed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpertHubCard));
    await tester.pumpAndSettle();

    expect(find.byType(ExpertLandingPickerDialog), findsOneWidget);
    expect(completed, isFalse);
  });

  testWidgets('dismiss returns null', (tester) async {
    final cubit = await pumpCubit([_member('Gamma')]);
    addTearDown(cubit.close);

    Object? sentinel = 'unset';
    await pumpHost(
      tester,
      cubit: cubit,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              sentinel = await showExpertLandingPickerSheet(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(ExpertLandingPickerDialog), findsNothing);
    expect(sentinel, isNull);
  });

  testWidgets('apply mode confirm invokes onApply', (tester) async {
    final member = _member('Delta');
    final cubit = await pumpCubit([member]);
    addTearDown(cubit.close);

    DiscoverableMember? applied;
    await pumpHost(
      tester,
      cubit: cubit,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              await showExpertApplyPickerSheet(
                context,
                onApply: (m) => applied = m,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpertHubCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(applied?.key, member.key);
    expect(find.byType(ExpertLandingPickerDialog), findsNothing);
  });
}
