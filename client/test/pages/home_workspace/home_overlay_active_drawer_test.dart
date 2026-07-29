import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  testWidgets('active keep-alive layer owns mobile overlay drawer', (
    tester,
  ) async {
    var homeActive = true;
    late StateSetter setParent;

    final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          setParent = setState;
          return MediaQuery(
            data: const MediaQueryData(size: Size(400, 800)),
            child: MaterialApp(
              theme: ThemeData(colorScheme: scheme, useMaterial3: true),
              home: TpTheme(
                data: TpThemeData.fromColorScheme(scheme, scale: 1.0),
                child: TpSidebarProvider(
                  mobileBreakpoint: 840,
                  openMobile: true,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      TpSidebar(
                        overlayActive: homeActive,
                        child: const Text('HOME-NAV'),
                      ),
                      TpSidebar(
                        overlayActive: !homeActive,
                        child: const Text('WS-NAV'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOME-NAV'), findsOneWidget);
    expect(find.text('WS-NAV'), findsNothing);

    setParent(() => homeActive = false);
    await tester.pumpAndSettle();

    expect(find.text('HOME-NAV'), findsNothing);
    expect(find.text('WS-NAV'), findsOneWidget);
  });
}
