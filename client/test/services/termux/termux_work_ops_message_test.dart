import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations_en.dart';
import 'package:teampilot/services/termux/termux_work_ops_message.dart';

void main() {
  tearDown(TermuxWorkOpsMessage.resetForTesting);

  test('disconnectedBlocked uses bound l10n', () {
    TermuxWorkOpsMessage.bind(AppLocalizationsEn());
    expect(
      TermuxWorkOpsMessage.disconnectedBlocked(),
      AppLocalizationsEn().termuxDisconnectedWorkOpsBlocked,
    );
  });

  test('disconnectedBlocked falls back before bind', () {
    expect(
      TermuxWorkOpsMessage.disconnectedBlocked(),
      contains('Termux is disconnected'),
    );
  });
}
