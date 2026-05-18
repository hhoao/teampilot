import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/team_config.dart';

/// Launch-time environment for tool-isolated team profiles.
typedef TeamLaunchEnvironment = Map<String, String>;
typedef ConfigProfileDirectoryCreator = Future<void> Function(String path);

/// Ensures team runtime isolation directories and returns launch env vars.
///
/// Does not write provider native configs or team-level `llm_config.json`.
class ConfigProfileService {
  static const flashskyaiMetadataFileName = '.flashskyai.json';

  static const Map<String, Object?> defaultFlashskyaiMetadata = {
    'hasCompletedOnboarding': true,
  };
  ConfigProfileService({
    required this.basePath,
    ConfigProfileDirectoryCreator? createDirectory,
  }) : _createDirectory = createDirectory ?? _createLocalDirectory;

  final String basePath;
  final ConfigProfileDirectoryCreator _createDirectory;

  String get configProfilesDir => p.join(basePath, 'config-profiles');

  String get commonFlashskyaiDir =>
      p.join(configProfilesDir, 'common', 'flashskyai');

  String get commonFlashskyaiLlmConfigFile =>
      p.join(commonFlashskyaiDir, 'llm_config.json');

  String commonProfileDirForTool(String tool) =>
      p.join(configProfilesDir, 'common', tool.trim());

  String teamProfileDir(String teamId) =>
      p.join(configProfilesDir, 'teams', teamId.trim());

  String teamToolDir(String teamId, String tool) =>
      p.join(teamProfileDir(teamId), tool);

  String teamFlashskyaiMetadataFile(String teamId) => p.join(
        teamToolDir(teamId, 'flashskyai'),
        flashskyaiMetadataFileName,
      );

  Future<void> ensureCommonProfiles() async {
    await _createDirectory(commonFlashskyaiDir);
  }

  Future<void> ensureTeamProfile(
    String teamId, {
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;

    await _createDirectory(teamToolDir(trimmed, cli.value));
    switch (cli) {
      case TeamCli.flashskyai:
        await ensureCommonProfiles();
        await ensureTeamFlashskyaiDefaults(trimmed);
      case TeamCli.codex:
      case TeamCli.claude:
        break;
    }
  }

  /// Seeds `.flashskyai.json` so the CLI skips first-run onboarding UI.
  Future<void> ensureTeamFlashskyaiDefaults(String teamId) async {
    final trimmed = teamId.trim();
    if (trimmed.isEmpty) return;

    final file = File(teamFlashskyaiMetadataFile(trimmed));
    if (await file.exists()) return;

    await file.parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(defaultFlashskyaiMetadata),
    );
  }

  /// Creates dirs for [cli] and returns launch env vars for that CLI only.
  Future<TeamLaunchEnvironment> prepareTeamLaunch({
    required String teamId,
    TeamCli cli = TeamCli.flashskyai,
  }) async {
    final trimmedTeamId = teamId.trim();
    if (trimmedTeamId.isEmpty) {
      return const {};
    }

    await ensureTeamProfile(trimmedTeamId, cli: cli);

    return switch (cli) {
      TeamCli.flashskyai => {
          'FLASHSKYAI_CONFIG_DIR': teamToolDir(trimmedTeamId, 'flashskyai'),
          'LLM_CONFIG_PATH': commonFlashskyaiLlmConfigFile,
        },
      TeamCli.codex => {
          'CODEX_HOME': teamToolDir(trimmedTeamId, 'codex'),
        },
      TeamCli.claude => {
          'CLAUDE_CONFIG_DIR': teamToolDir(trimmedTeamId, 'claude'),
        },
    };
  }

  static Future<void> _createLocalDirectory(String path) =>
      Directory(path).create(recursive: true);
}
