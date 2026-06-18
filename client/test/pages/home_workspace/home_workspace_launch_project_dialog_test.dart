import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/launch_identity.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_launch_project_dialog.dart';
import 'package:teampilot/services/storage/identity_provisioner.dart';

void main() {
  testWidgets('returns selected personal identity from the list',
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
                result = await showHomeLaunchWorkspaceDialog(
                  context,
                  projectName: 'Repo',
                  identities: const <LaunchProjectIdentityOption>[
                    LaunchProjectIdentityOption(
                      id: IdentityProvisioner.defaultPersonalId,
                      name: 'Default',
                      isTeam: false,
                    ),
                    LaunchProjectIdentityOption(
                      id: 't1',
                      name: 'Backend',
                      isTeam: true,
                    ),
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

    await tester.tap(find.text('Default'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(
      result!.identity,
      const LaunchIdentity(IdentityProvisioner.defaultPersonalId),
    );
    expect(result!.remember, isFalse);
  });
}
