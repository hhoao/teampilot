import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/app_text_scale_boundary.dart';

void main() {
  testWidgets('replaces inherited textScaler with noScaling', (tester) async {
    late TextScaler seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: AppTextScaleBoundary(
          child: Builder(
            builder: (context) {
              seen = MediaQuery.textScalerOf(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(seen, TextScaler.noScaling);
  });
}
