import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/terminal/pty_launch_environment.dart';
import 'package:teampilot/services/terminal/terminal_session.dart';
import 'package:teampilot/services/terminal/terminal_theme_for_launch.dart';
import 'package:teampilot/services/terminal/terminal_transport.dart';

class _FakeTransport implements TerminalTransport {
  final outputController = StreamController<Uint8List>();
  final doneCompleter = Completer<int>();

  @override
  Stream<Uint8List> get output => outputController.stream;

  @override
  Future<int> get done => doneCompleter.future;

  @override
  int? get pid => null;

  @override
  void close() {
    if (!doneCompleter.isCompleted) doneCompleter.complete(0);
  }

  @override
  void resize(int rows, int columns) {}

  @override
  void write(Uint8List data) {}
}

String get _ptyTestExecutable {
  if (Platform.isWindows) {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    return '$root\\System32\\cmd.exe';
  }
  for (final candidate in ['/usr/bin/true', '/bin/true', '/bin/sh']) {
    if (File(candidate).existsSync()) return candidate;
  }
  return Platform.resolvedExecutable;
}

void main() {
  test('resolveTerminalThemeFromLayout light mode yields light COLORFGBG bg', () {
    final theme = resolveTerminalThemeFromLayout(
      preferences: const LayoutPreferences(themeMode: 'light'),
      platformBrightness: Brightness.dark,
    );
    final env = <String, String>{};
    PtyLaunchEnvironment.applyColorScheme(env, background: theme.background);
    expect(env['COLORFGBG'], '0;15');
  });

  test('resolveTerminalThemeFromLayout dark mode yields dark COLORFGBG bg', () {
    final theme = resolveTerminalThemeFromLayout(
      preferences: const LayoutPreferences(themeMode: 'dark'),
      platformBrightness: Brightness.light,
    );
    final env = <String, String>{};
    PtyLaunchEnvironment.applyColorScheme(env, background: theme.background);
    expect(env['COLORFGBG'], '15;0');
  });

  test(
    'applyShellTerminalThemeForLaunch before connect sets COLORFGBG on PTY env',
    () async {
      Map<String, String>? capturedEnv;
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable: _ptyTestExecutable,
        validateLaunch: false,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              capturedEnv = environment;
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      const lightBg = TerminalTheme(
        background: 0xF7F9FC,
        foreground: 0x3D3A42,
        selection: 0xD4A06A,
        ansi: [
          0x2A2A2A,
          0xB00020,
          0x007A4B,
          0x8A6D00,
          0x005FCC,
          0x7A3DB8,
          0x006A85,
          0x6B6670,
          0x666666,
          0xD32F2F,
          0x0A8F5A,
          0xA88700,
          0x1976D2,
          0x9C4DCC,
          0x008DB3,
          0x3D3A42,
        ],
        searchMatch: (bg: 0xFFFF2B, fg: 0x000000),
        searchFocused: (bg: 0x31FF26, fg: 0x000000),
        hintStart: (bg: 0x005FCC, fg: 0xFFFFFF),
        cursorText: null,
        cursorColor: 0x005FCC,
        bellOverlay: 0xFFFFFF,
      );

      // Background member shells historically connected without a theme; that
      // left COLORFGBG unset/wrong so Claude `theme: auto` picked dark.
      applyShellTerminalThemeForLaunch(session, lightBg);
      session.connect(workingDirectory: Directory.systemTemp.path);
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(capturedEnv?['COLORFGBG'], '0;15');
    },
  );

  test(
    'connect without applyShellTerminalThemeForLaunch leaves COLORFGBG unset by us',
    () async {
      Map<String, String>? capturedEnv;
      final handle = _FakeTransport();
      final session = TerminalSession(
        executable: _ptyTestExecutable,
        validateLaunch: false,
        transportStarter:
            (
              executable, {
              required arguments,
              required workingDirectory,
              required columns,
              required rows,
              environment,
            }) {
              capturedEnv = environment;
              return Future.value(handle);
            },
      );
      addTearDown(() async {
        session.dispose();
        await handle.outputController.close();
      });

      session.connect(workingDirectory: Directory.systemTemp.path);
      session.onViewportResize(80, 24);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(capturedEnv?['COLORFGBG'], Platform.environment['COLORFGBG']);
    },
  );
}
