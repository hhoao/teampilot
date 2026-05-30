import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/host/macos_npm_path_candidates.dart';

void main() {
  test('paths follow platform', () {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      expect(
        MacOsNpmPathCandidates.paths(),
        [
          '/opt/homebrew/bin/npm',
          '/usr/local/bin/npm',
          if (home != null) '$home/.local/bin/npm',
        ],
      );
      return;
    }
    expect(MacOsNpmPathCandidates.paths(), isEmpty);
  });
}
