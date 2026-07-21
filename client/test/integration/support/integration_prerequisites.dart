import 'dart:ffi';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Shared skip gates and PATH resolution for integration tests.
abstract final class IntegrationPrerequisites {
  static const skipWithoutNativePty =
      'Requires flutter_pty_new native library (run `flutter build linux` or '
      '`flutter build windows` and set loader path as in DEVELOPMENT.md)';

  static void resetHttpOverrides() {
    HttpOverrides.global = null;
  }

  /// True when `libflutter_pty_new` / `flutter_pty_new.dll` is on the loader path.
  static bool get nativePtyAvailable {
    if (Platform.isLinux) {
      const candidates = [
        'libflutter_pty_new.so',
        'build/linux/x64/debug/bundle/lib/libflutter_pty_new.so',
        'build/linux/x64/debug/plugins/flutter_pty_new/shared/libflutter_pty_new.so',
      ];
      for (final path in candidates) {
        try {
          DynamicLibrary.open(path);
          return true;
        } catch (_) {}
      }
      return false;
    }
    if (Platform.isWindows) {
      for (final path in [
        'flutter_pty_new.dll',
        r'build\windows\x64\debug\flutter_pty_new.dll',
        r'build\windows\x64\runner\Debug\flutter_pty_new.dll',
      ]) {
        try {
          DynamicLibrary.open(path);
          return true;
        } catch (_) {}
      }
    }
    return false;
  }

  /// Resolves `claude` on PATH, or null when not installed.
  static String? resolveClaudePath() {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('where', ['claude']);
        if (result.exitCode != 0) return null;
        for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final resolved = _resolveWindowsExecutablePath(line);
          if (resolved != null) return resolved;
        }
        return null;
      }
      final result = Process.runSync('which', ['claude']);
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split('\n').first.trim();
      return line.isEmpty ? null : line;
    } on ProcessException {
      return null;
    }
  }

  static String? requireClaudePath() {
    final path = resolveClaudePath();
    if (path == null) {
      markTestSkipped('claude not on PATH');
    }
    return path;
  }

  /// Resolves `flashskyai` on PATH, or null when not installed.
  static String? resolveFlashskyaiPath() {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('where', ['flashskyai']);
        if (result.exitCode != 0) return null;
        for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final resolved = _resolveWindowsExecutablePath(line);
          if (resolved != null) return resolved;
        }
        return null;
      }
      final result = Process.runSync('which', ['flashskyai']);
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split('\n').first.trim();
      return line.isEmpty ? null : line;
    } on ProcessException {
      return null;
    }
  }

  static String? requireFlashskyaiPath() {
    final path = resolveFlashskyaiPath();
    if (path == null) {
      markTestSkipped('flashskyai not on PATH');
    }
    return path;
  }

  /// Resolves `codex` on PATH, or null when not installed.
  static String? resolveCodexPath() {
    try {
      if (Platform.isWindows) {
        final result = Process.runSync('where', ['codex']);
        if (result.exitCode != 0) return null;
        for (final raw in result.stdout.toString().split(RegExp(r'\r?\n'))) {
          final line = raw.trim();
          if (line.isEmpty) continue;
          final resolved = _resolveWindowsExecutablePath(line);
          if (resolved != null) return resolved;
        }
        return null;
      }
      final result = Process.runSync('which', ['codex']);
      if (result.exitCode != 0) return null;
      final line = result.stdout.toString().trim().split('\n').first.trim();
      return line.isEmpty ? null : line;
    } on ProcessException {
      return null;
    }
  }

  static String? requireCodexPath() {
    final path = resolveCodexPath();
    if (path == null) {
      markTestSkipped('codex not on PATH');
    }
    return path;
  }

  static void skipUnlessNativePty() {
    if (!nativePtyAvailable) {
      markTestSkipped(skipWithoutNativePty);
    }
  }

  static String? _resolveWindowsExecutablePath(String candidate) {
    for (final suffix in ['.cmd', '.exe', '.bat']) {
      final withSuffix = '$candidate$suffix';
      if (File(withSuffix).existsSync()) return withSuffix;
    }
    final lower = candidate.toLowerCase();
    if (File(candidate).existsSync() &&
        (lower.endsWith('.exe') ||
            lower.endsWith('.cmd') ||
            lower.endsWith('.bat'))) {
      return candidate;
    }
    return null;
  }
}
