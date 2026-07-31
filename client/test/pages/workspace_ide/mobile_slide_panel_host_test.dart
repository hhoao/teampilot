import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/pages/workspace_ide/mobile_slide_panel_host.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  testWidgets(
    'losing overlayActive does not setState during build',
    (tester) async {
      var openMobile = true;
      late void Function(void Function()) setHarnessState;

      await tester.pumpWidget(
        TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            scale: 1.0,
          ),
          child: TpSidebarProvider(
            mobileBreakpoint: WorkspacePanePolicy.narrowBreakpointWidth,
            child: MaterialApp(
              home: StatefulBuilder(
                builder: (context, setState) {
                  setHarnessState = setState;
                  final scope = TpSidebarScope.of(context);
                  // Mirror shared openMobile via provider when harness flips.
                  return Scaffold(
                    body: MobileSlidePanelHost(
                      open: openMobile,
                      overlayActive: openMobile, // lose both together
                      width: 280,
                      onDismiss: () {},
                      onReleaseOverlayOwnership: () {
                        scope.setOpenMobile(false);
                      },
                      panel: const Text('PANEL'),
                      child: const Text('CHILD'),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('PANEL'), findsOneWidget);

      // Flip ownership during a normal setState rebuild — must not throw.
      setHarnessState(() {
        openMobile = false;
      });
      await tester.pump();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('PANEL'), findsNothing);
    },
  );
}
