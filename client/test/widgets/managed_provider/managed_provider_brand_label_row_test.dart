import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/managed_provider/managed_provider_brand_icon.dart';

void main() {
  testWidgets('brand label row vertically centers icon and text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ManagedProviderBrandLabelRow(
            leading: Container(
              key: const Key('leading'),
              width: 15,
              height: 15,
              color: Colors.red,
            ),
            label: 'Codex',
            iconSize: 15,
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    await tester.pump();

    final icon = tester.getRect(find.byKey(const Key('leading')));
    final label = tester.getRect(find.text('Codex'));
    expect((icon.center.dy - label.center.dy).abs(), lessThanOrEqualTo(0.5));
    expect(tester.takeException(), isNull);
  });
}
