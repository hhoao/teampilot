import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/bundled_asset_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads team-lead deny hook ps1 from bundle or disk', () async {
    final script = await loadBundledAssetString(
      'assets/hooks/teampilot-deny-team-lead-self-message.ps1',
    );
    expect(script, contains('SendMessage'));
    expect(script, contains('team-lead'));
  });

  test('loads team-lead deny hook sh from bundle or disk', () async {
    final script = await loadBundledAssetString(
      'assets/hooks/teampilot-deny-team-lead-self-message.sh',
    );
    expect(script, contains('SendMessage'));
  });
}
