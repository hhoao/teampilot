import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/macos_npm_path_candidates.dart';

void main() {
  test('paths is empty off macOS', () {
    // Test runs on Linux CI; candidates are macOS-only.
    expect(MacOsNpmPathCandidates.paths(), isEmpty);
  });
}
