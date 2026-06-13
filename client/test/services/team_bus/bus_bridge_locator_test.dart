import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/team_bus/mcp/bus_bridge_locator.dart';

void main() {
  group('BusBridgeLocator.isRunnableExecutable', () {
    test('returns false for missing path', () {
      expect(
        BusBridgeLocator.isRunnableExecutable('/nonexistent/teammate_bus_bridge'),
        isFalse,
      );
    });

    test('returns true for a runnable script on this platform', () async {
      final dir = await Directory.systemTemp.createTemp('bus_bridge_locator_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final script = File('${dir.path}/mock_bridge${Platform.isWindows ? '.bat' : ''}');
      if (Platform.isWindows) {
        await script.writeAsString('@echo off\r\nexit /b 2\r\n');
      } else {
        await script.writeAsString('#!/bin/sh\nexit 2\n');
        await Process.run('chmod', ['+x', script.path]);
      }

      expect(BusBridgeLocator.isRunnableExecutable(script.path), isTrue);
    });
  });
}
