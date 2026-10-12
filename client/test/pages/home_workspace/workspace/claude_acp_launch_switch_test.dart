import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/claude_acp_launch_switch.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';

void main() {
  group('resolveLaunchAcp', () {
    test('true only for personal Claude when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.claude,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('true for personal Cursor when requested on desktop', () {
      expect(
        resolveLaunchAcp(
          isPersonal: true,
          cli: CliTool.cursor,
          requested: true,
          isAndroidOverride: false,
        ),
        isTrue,
      );
    });

    test('false for team, Gemini, not requested, or Android', () {
      bool resolve({
        bool isPersonal = true,
        CliTool? cli = CliTool.claude,
        bool requested = true,
        bool isAndroid = false,
      }) => resolveLaunchAcp(
        isPersonal: isPersonal,
        cli: cli,
        requested: requested,
        isAndroidOverride: isAndroid,
      );
      expect(resolve(isPersonal: false), isFalse);
      expect(resolve(cli: CliTool.gemini), isFalse);
      expect(resolve(cli: null), isFalse);
      expect(resolve(requested: false), isFalse);
      expect(resolve(isAndroid: true), isFalse);
      expect(
        resolve(cli: CliTool.cursor, isAndroid: true),
        isFalse,
      );
    });
  });

  group('buildWorkspaceConversationCreateRequest', () {
    final workspace = Workspace(workspaceId: 'ws', createdAt: 1);

    test('personal Claude with ACP requested sets request.acp', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isTrue);
    });

    test('defaults to acp false until the caller passes the settings flag', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('team create stays false even when acp is requested', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: false,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: false,
      );
      expect(request.acp, isFalse);
    });

    test('Android forces acp false', () {
      final request = buildWorkspaceConversationCreateRequest(
        workspace: workspace,
        isPersonal: true,
        cli: CliTool.claude,
        acp: true,
        isAndroidOverride: true,
      );
      expect(request.acp, isFalse);
    });
  });
}
