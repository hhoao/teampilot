import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';

void main() {
  group('parseXdgDocumentsDir', () {
    test('resolves \$HOME-relative XDG_DOCUMENTS_DIR', () {
      final result = DefaultWorkspaceDirectory.parseXdgDocumentsDir(
        'XDG_DOCUMENTS_DIR="\$HOME/Document"\n',
        home: '/home/hhoa',
      );
      expect(result, '/home/hhoa/Document');
    });

    test('resolves absolute XDG_DOCUMENTS_DIR', () {
      final result = DefaultWorkspaceDirectory.parseXdgDocumentsDir(
        'XDG_DOCUMENTS_DIR="/data/docs"\n',
        home: '/home/hhoa',
      );
      expect(result, '/data/docs');
    });

    test('ignores comments and unrelated entries', () {
      final result = DefaultWorkspaceDirectory.parseXdgDocumentsDir(
        '# written by xdg-user-dirs-update\n'
        'XDG_DESKTOP_DIR="\$HOME/Desktop"\n'
        'XDG_DOCUMENTS_DIR="\$HOME/Document"\n'
        'XDG_MUSIC_DIR="\$HOME/Music"\n',
        home: '/home/hhoa',
      );
      expect(result, '/home/hhoa/Document');
    });

    test('returns null when unset', () {
      final result = DefaultWorkspaceDirectory.parseXdgDocumentsDir(
        'XDG_DESKTOP_DIR="\$HOME/Desktop"\n',
        home: '/home/hhoa',
      );
      expect(result, isNull);
    });
  });

  group('teamPilotDirFromDocuments', () {
    test('nests TeamPilot under the documents dir', () {
      expect(
        DefaultWorkspaceDirectory.teamPilotDirFromDocuments(
          '/home/hhoa/Document',
        ),
        '/home/hhoa/Document/TeamPilot',
      );
    });

    test('uses POSIX separators for POSIX-style roots', () {
      expect(
        DefaultWorkspaceDirectory.teamPilotDirFromDocuments('/tp/Document'),
        '/tp/Document/TeamPilot',
      );
    });
  });

  test('platformDocumentsFastPath resolves a documents dir from HOME', () {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final fast = DefaultWorkspaceDirectory.platformDocumentsFastPathForTesting();
    expect(fast, isNotNull);
  });
}
