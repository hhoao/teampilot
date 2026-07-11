import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/theme/font_catalog.dart';
import 'package:teampilot/widgets/dropdown/app_dropdown_field.dart';
import 'package:teampilot/widgets/settings/font_preference_setting.dart';

import '../../support/post_frame_test_harness.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  setUpTestAppStorage();
  tearDown(tearDownTestAppStorage);

  testWidgets('renders a searchable font dropdown', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FontPreferenceSetting(
          role: FontRole.ui,
          value: FontCatalog.systemId,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(AppDropdownField<String>), findsOneWidget);
    expect(find.text('System'), findsOneWidget);
  });
}
