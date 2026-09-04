import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/utils/session/session_display_title.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final zh = lookupAppLocalizations(const Locale('zh'));

  AppSession session({
    String display = '',
    SessionPurpose purpose = SessionPurpose.normal,
  }) {
    return AppSession(
      sessionId: 's1',
      workspaceId: 'w1',
      folders: const [WorkspaceFolder(path: '/tmp')],
      display: display,
      createdAt: 1,
      purpose: purpose,
      workflowId: purpose == SessionPurpose.teamGeneration
          ? '00000000-0000-4000-8000-000000000001'
          : '',
    );
  }

  test('trims and collapses whitespace', () {
    expect(
      deriveSessionTitleFromFirstPrompt('  fix   the   bug  '),
      'fix the bug',
    );
  });

  test('uses first line only', () {
    expect(deriveSessionTitleFromFirstPrompt('line one\nline two'), 'line one');
  });

  test('truncates with ellipsis', () {
    final long = 'a' * 60;
    expect(
      deriveSessionTitleFromFirstPrompt(long, maxLength: 10),
      '${'a' * 9}…',
    );
  });

  test('returns empty for blank input', () {
    expect(deriveSessionTitleFromFirstPrompt('   '), '');
  });

  test('team generation empty display uses localized builder title', () {
    final s = session(purpose: SessionPurpose.teamGeneration);
    expect(sessionListDisplayTitle(s, en), 'Team Builder');
    expect(sessionListDisplayTitle(s, zh), '团队构建器');
  });

  test('team generation legacy English display still localizes', () {
    final s = session(
      purpose: SessionPurpose.teamGeneration,
      display: 'Team Builder',
    );
    expect(sessionListDisplayTitle(s, zh), '团队构建器');
  });

  test('team generation custom display is kept', () {
    final s = session(
      purpose: SessionPurpose.teamGeneration,
      display: 'My builder',
    );
    expect(sessionListDisplayTitle(s, zh), 'My builder');
  });

  test('normal empty display falls back to new chat', () {
    expect(sessionListDisplayTitle(session(), zh), '新对话');
  });
}
