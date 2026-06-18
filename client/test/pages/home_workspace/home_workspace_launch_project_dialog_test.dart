import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_launch_project_dialog.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

void main() {
  testWidgets('returns personal identity when simple mode is chosen',
      (tester) async {
    LaunchProjectChoice? result;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        return Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showHomeWorkspaceLaunchProjectDialog(
                  context,
                  projectName: 'Repo',
                  teams: const <LaunchProjectTeamOption>[
                    LaunchProjectTeamOption(id: 't1', name: 'Backend'),
                  ],
                );
              },
              child: const Text('open'),
            ),
          ),
        );
      }),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Simple mode'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(
      result!.identity,
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId),
    );
    expect(result!.remember, isFalse);
  });
}
