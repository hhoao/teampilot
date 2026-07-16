import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/theme/team_pilot_toast_config.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

class _RecordingRecorder implements NotificationRecorder {
  final records = <({String message, TpToastVariant variant})>[];

  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
  }) {
    records.add((message: message, variant: variant));
  }
}

Widget _harness({required Widget child}) {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.indigo);
  return TpToastWrapper(
    config: buildTeamPilotToastConfig(),
    child: MaterialApp(
      theme: ThemeData(colorScheme: scheme),
      home: TpTheme(
        data: TpThemeData.fromColorScheme(scheme, scale: 1),
        child: child,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    NotificationRecorder.install(null);
    TpToast.dismiss();
  });

  testWidgets('AppToast.show records non-info toasts', (tester) async {
    final recorder = _RecordingRecorder();
    NotificationRecorder.install(recorder);

    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => AppToast.show(
                context,
                message: 'Saved',
                variant: TpToastVariant.success,
              ),
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(recorder.records, hasLength(1));
    expect(recorder.records.single.message, 'Saved');
    expect(recorder.records.single.variant, TpToastVariant.success);

    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('AppToast.show does not record info toasts', (tester) async {
    final recorder = _RecordingRecorder();
    NotificationRecorder.install(recorder);

    await tester.pumpWidget(
      _harness(
        child: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () => AppToast.show(
                context,
                message: 'FYI',
                variant: TpToastVariant.info,
              ),
              child: const Text('go'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(recorder.records, isEmpty);

    TpToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });
}
