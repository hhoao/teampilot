import 'package:teampilot_search/teampilot_search.dart';
import 'package:test/test.dart';

void main() {
  test('rust core loads and reports version', () {
    expect(engineVersion(), startsWith('teampilot_search/'));
  });
}
