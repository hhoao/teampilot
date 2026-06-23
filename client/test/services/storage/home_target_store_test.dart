import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/services/storage/home_target_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('empty by default', () async {
    final prefs = await SharedPreferences.getInstance();
    expect(HomeTargetStore(prefs).load(), '');
  });

  test('save then load round-trips', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = HomeTargetStore(prefs);
    await store.save('ssh:p1');
    expect(store.load(), 'ssh:p1');
  });
}
