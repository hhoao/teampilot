import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_usage_dashboard.dart';
import 'package:teampilot/pages/usage/usage_format.dart';

void main() {
  test('usageChartLabelStride keeps about seven bottom labels', () {
    expect(usageChartLabelStride(0), 1);
    expect(usageChartLabelStride(1), 1);
    expect(usageChartLabelStride(7), 1);
    expect(usageChartLabelStride(14), 2);
    expect(usageChartLabelStride(30), 5);
  });

  testWidgets('range labels cover all presets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            expect(
              usageRangeLabel(context, UsageRange.last24Hours),
              'Last 24 hours',
            );
            expect(
              usageRangeLabel(context, UsageRange.fourteenDays),
              'Last 14 days',
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });
}
