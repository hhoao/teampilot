import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/home_workspace/clone_repository_dialog.dart';
import 'package:teampilot/services/storage/home_target_controller.dart';
import 'package:teampilot/services/workspace/repo_clone_service.dart';

import '../../support/test_home_target_controller.dart';

Widget _harness({GlobalKey<NavigatorState>? navigatorKey, Widget? home}) {
  final theme = ThemeData(useMaterial3: true);
  return TpTheme(
    data: TpThemeData.fromColorScheme(theme.colorScheme, scale: 1.0),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: theme,
      home: Scaffold(body: Center(child: home ?? const SizedBox.shrink())),
    ),
  );
}

/// Routes [dialog] onto the navigator and returns the future that resolves
/// with whatever the dialog pops.
Future<RepoCloneRequest?> _pushDialog(
  GlobalKey<NavigatorState> navigatorKey,
  Widget dialog,
) {
  final result = navigatorKey.currentState!.push<RepoCloneRequest>(
    MaterialPageRoute<RepoCloneRequest>(
      builder: (_) => Scaffold(body: Center(child: dialog)),
    ),
  );
  return result;
}

/// The parent-directory picker seam injected for tests.
Future<String?> _fakePicker(BuildContext context, String targetId) async =>
    '/tmp/src';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final navigatorKey = GlobalKey<NavigatorState>();

  HomeTargetController homeController() => testHomeTargetController();

  Widget dialog({ pickerFn }) => RepositoryProvider<HomeTargetController>.value(
    value: homeController(),
    child: HomeCloneRepositoryDialog(picker: pickerFn),
  );

  testWidgets('invalid URL shows validation error and does not pop', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    var popped = false;
    _pushDialog(navigatorKey, dialog()).then((value) {
      if (value != null) popped = true;
    });
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'not a url',
    );
    await tester.pump();
    await tester.tap(find.text(l10n.cloneRepositorySubmit));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cloneRepositoryUrlInvalid), findsOneWidget);
    expect(popped, isFalse,
        reason: 'invalid form must not pop the dialog route');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('valid URL derives folder name', (tester) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    _pushDialog(navigatorKey, dialog());
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://github.com/owner/repo.git',
    );
    await tester.pump();

    // Second TextField is the dir-name field (URL field is first).
    final dirField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(dirField.controller?.text, 'repo');
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('missing parent dir shows required error and does not pop', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    var popped = false;
    _pushDialog(navigatorKey, dialog()).then((value) {
      if (value != null) popped = true;
    });
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://github.com/owner/repo.git',
    );
    await tester.pump();
    await tester.tap(find.text(l10n.cloneRepositorySubmit));
    await tester.pumpAndSettle();

    expect(find.text(l10n.cloneRepositoryParentDirRequired), findsOneWidget);
    expect(popped, isFalse);
    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('submit with target + dir + parent pops a RepoCloneRequest', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(navigatorKey: navigatorKey));
    RepoCloneRequest? popped;
    _pushDialog(navigatorKey, dialog(pickerFn: _fakePicker)).then((value) {
      popped = value;
    });
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'https://github.com/owner/repo.git',
    );
    await tester.pump();
    await tester.tap(find.text(l10n.homeWorkspaceNewWorkspaceChooseDirectory));
    await tester.pump();

    await tester.tap(find.text(l10n.cloneRepositorySubmit));
    await tester.pumpAndSettle();

    expect(popped, isA<RepoCloneRequest>());
    expect(popped!.url, 'https://github.com/owner/repo.git');
    expect(popped!.targetId, 'local');
    expect(popped!.parentDir, '/tmp/src');
    expect(popped!.dirName, 'repo');
    await tester.pumpAndSettle();
  });
}
