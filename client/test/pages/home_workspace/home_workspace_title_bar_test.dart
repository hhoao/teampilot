import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/notification_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_title_bar.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(() {
    setUpTestAppStorage();
  });
  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets('title bar renders personal and team tabs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlocProvider(
          create: (_) => NotificationCubit(),
          child: const HomeTitleBar(
            tabs: [
              HomeWorkspaceTab(
                id: 'personal',
                name: 'Solo',
                kind: HomeWorkspaceTabKind.personal,
              ),
              HomeWorkspaceTab(
                id: 'team',
                name: 'Shared',
                kind: HomeWorkspaceTabKind.team,
              ),
            ],
            activeWorkspaceId: 'personal',
          ),
        ),
      ),
    );

    expect(find.text('Solo'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.byType(HomeTitleBar), findsOneWidget);
  });
}
