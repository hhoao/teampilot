import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_storage.dart';

void main() {
  test('platformDocumentsFastPath resolves linux Documents from HOME', () {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final fast = DefaultWorkspaceDirectory.platformDocumentsFastPathForTesting();
    expect(fast, isNotNull);
    expect(fast, contains('Documents'));
  });
}
