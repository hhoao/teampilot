import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/widgets/window_chrome_controls.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('macOS traffic lights reveal symbols on hover', (tester) async {
    await tester.pumpWidget(
      wrap(
        MacTrafficLightControls(
          isMaximized: false,
          onMinimize: () async {},
          onToggleMaximize: () async {},
          onClose: () async {},
        ),
      ),
    );

    expect(find.byType(MacTrafficLightControls), findsOneWidget);
    expect(find.text('×'), findsNothing);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MacTrafficLightControls)));
    await tester.pump();

    expect(find.text('×'), findsOneWidget);
    expect(find.text('−'), findsOneWidget);
    expect(find.text('+'), findsOneWidget);
  });

  testWidgets('Windows chrome controls render icon buttons', (tester) async {
    await tester.pumpWidget(
      wrap(
        WindowsStyleChromeControls(
          isMaximized: false,
          onMinimize: () async {},
          onToggleMaximize: () async {},
          onClose: () async {},
        ),
      ),
    );

    expect(find.byIcon(Icons.remove), findsOneWidget);
    expect(find.byIcon(Icons.crop_square_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
