import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/pages/config/acp_proxy_machine_card.dart';
import 'package:teampilot/services/acp/acp_proxy_install.dart';
import 'package:teampilot/services/acp/acp_proxy_route.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

void main() {
  const missing = AcpProxyProbeSnapshot(
    binaryPresent: false,
    pidFile: '',
    advertisementJson: null,
    tcpTable: '',
    advertisementFdLinks: [],
    pidFileFdLinks: [],
  );

  Widget app({
    Future<AcpProxyProbeSnapshot> Function()? loadStatus,
    Future<CliInstallResult> Function(AcpProxyCardAction action)? runAction,
  }) {
    return MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: appLocalizationsSupportedLocales,
      home: Scaffold(
        body: AcpProxyMachineCard(loadStatus: loadStatus, runAction: runAction),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  testWidgets('missing binary offers install', (tester) async {
    await tester.pumpWidget(app(loadStatus: () async => missing));
    await settle(tester);

    expect(find.text('Cloud keep-alive'), findsOneWidget);
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('a different version offers upgrade', (tester) async {
    await tester.pumpWidget(
      app(
        loadStatus: () async => const AcpProxyProbeSnapshot(
          binaryPresent: true,
          pidFile: '42',
          advertisementJson:
              '{"v":1,"version":"0.0.9","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}',
          tcpTable: '',
          advertisementFdLinks: [],
          pidFileFdLinks: [],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Upgrade'), findsOneWidget);
  });

  testWidgets('an installed proxy that is not listening offers start', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        loadStatus: () async => const AcpProxyProbeSnapshot(
          binaryPresent: true,
          pidFile: '42',
          advertisementJson:
              '{"v":1,"version":"0.1.0","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}',
          tcpTable: '',
          advertisementFdLinks: [],
          pidFileFdLinks: [],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Installed, not running'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
  });

  testWidgets('a listening proxy is ready and has no action', (tester) async {
    const table = '''
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 0100007F:1F90 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4242 1 0000000000000000 100 0 0 10 0
''';
    await tester.pumpWidget(
      app(
        loadStatus: () async => const AcpProxyProbeSnapshot(
          binaryPresent: true,
          pidFile: '42',
          advertisementJson:
              '{"v":1,"version":"0.1.0","bind":"127.0.0.1","pid":42,"clis":{"claude":{"port":8080}}}',
          tcpTable: table,
          advertisementFdLinks: ['socket:[4242]'],
          pidFileFdLinks: ['socket:[4242]'],
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Ready'), findsOneWidget);
    expect(find.byKey(AppKeys.acpProxyActionButton), findsNothing);
  });

  testWidgets('a probe error retries instead of installing', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      app(
        loadStatus: () async {
          calls++;
          if (calls == 1) throw StateError('down');
          return missing;
        },
      ),
    );
    await settle(tester);

    expect(find.textContaining('down'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Install'), findsNothing);

    await tester.tap(find.byKey(AppKeys.acpProxyActionButton));
    await settle(tester);

    expect(calls, 2);
    expect(find.text('Not installed'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);
  });

  testWidgets('install runs the injected action', (tester) async {
    AcpProxyCardAction? seen;
    await tester.pumpWidget(
      app(
        loadStatus: () async => missing,
        runAction: (action) async {
          seen = action;
          return const CliInstallResult(success: true, message: 'ok');
        },
      ),
    );
    await settle(tester);

    await tester.tap(find.byKey(AppKeys.acpProxyActionButton));
    await settle(tester);

    expect(seen, AcpProxyCardAction.install);
  });
}
