import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/app/app_text_field_warmup.dart';
import 'package:teampilot/widgets/app_text_field_warmup_host.dart';

void main() {
  testWidgets('AppTextFieldWarmupHost completes immediately in tests', (
    tester,
  ) async {
    expect(AppTextFieldWarmup.isReady, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: AppTextFieldWarmupHost(
          child: Text('ready'),
        ),
      ),
    );

    expect(find.text('ready'), findsOneWidget);
    await AppTextFieldWarmup.whenReady;
  });
}
