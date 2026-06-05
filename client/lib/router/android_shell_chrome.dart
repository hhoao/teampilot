import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../cubits/team_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../pages/mcp/mcp_routes.dart';
import '../pages/mcp/mcp_management_page.dart';
import '../pages/skills/skill_management_page.dart';

/// Resolves Android [Scaffold] title, back affordance, and drawer visibility
/// for hub-style workspace routes (settings, team config, skills).
class AndroidShellChrome {
  const AndroidShellChrome._();

  static bool isHubDetailPath(String path) {
    if (_isConfigDetail(path)) return true;
    if (_isLlmProviderDetail(path)) return true;
    if (_isTeamConfigDetail(path)) return true;
    if (_isSkillsDetail(path)) return true;
    if (_isMcpDetail(path)) return true;
    return false;
  }

  static bool shouldHideDrawer(String path) => isHubDetailPath(path);

  static String title(BuildContext context, String path) {
    final l10n = context.l10n;
    if (path == '/config') return l10n.settings;
    if (path == '/config/layout') return l10n.layout;
    if (path == '/providers' || _isLlmCliRoot(path)) return l10n.llmConfig;
    if (_isLlmProviderDetail(path)) {
      if (path.endsWith('/edit')) return l10n.editProvider;
      if (path.endsWith('/add')) return l10n.addProvider;
      if (path.endsWith('/models')) return l10n.models;
      final name = _llmProviderNameFromPath(path);
      if (name != null) return name;
    }
    if (path == '/config/session') return l10n.session;
    if (path == '/config/cli') return l10n.cliConfig;
    if (path == '/config/ssh-profiles') return l10n.sshProfilesSettingsTitle;
    if (path == '/config/about') return l10n.aboutTitle;
    if (path == '/config/logs') return l10n.logViewerTitle;

    if (path == '/team-config') return l10n.teamConfig;
    if (path == '/team-config/team') return l10n.teamSettings;
    if (path == '/team-config/skills') return l10n.teamSkillsNav;
    if (path == '/team-config/mcp') return l10n.teamMcpNav;
    if (path == '/mcp') return l10n.mcpNavTitle;
    if (path == '/mcp/add') return l10n.mcpAddTitle;
    if (path.startsWith('/mcp/edit/')) return l10n.mcpEdit;
    if (path.startsWith('/mcp/')) {
      final segment = path.replaceFirst('/mcp/', '').split('/').first;
      for (final section in McpSection.values) {
        if (section.routeSegment == segment) {
          return section.title(l10n);
        }
      }
    }
    if (path.startsWith('/team-config/members/')) {
      return _memberTitle(context, path) ?? l10n.members;
    }

    if (path == '/skills') return l10n.skillsTitle;
    if (path.startsWith('/skills/')) {
      final segment = path.replaceFirst('/skills/', '');
      for (final section in SkillSection.values) {
        if (section.routeSegment == segment) {
          return section.title(l10n);
        }
      }
    }

    return 'FlashSkyAI';
  }

  static void pop(BuildContext context, String path) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    if (_isLlmProviderDetail(path)) {
      if (path.endsWith('/models')) {
        context.pop();
        return;
      }
      context.go(_llmCliRootFromPath(path) ?? '/providers');
      return;
    }
    if (_isConfigDetail(path) || path == '/config') {
      context.go('/config');
      return;
    }
    if (_isTeamConfigDetail(path) || path == '/team-config') {
      context.go('/team-config');
      return;
    }
    if (_isSkillsDetail(path) || path == '/skills') {
      context.go('/skills');
      return;
    }
    if (mcpPathIsForm(path)) {
      context.go(mcpInstalledRoute);
      return;
    }
    if (_isMcpDetail(path) || path == '/mcp') {
      context.go('/mcp');
    }
  }

  static bool _isConfigDetail(String path) =>
      path.startsWith('/config/') && path.length > '/config/'.length;

  static bool _isLlmProviderDetail(String path) =>
      path.startsWith('/providers/') && path.contains('/provider/');

  static String? _llmProviderNameFromPath(String path) {
    final marker = '/provider/';
    final idx = path.indexOf(marker);
    if (idx < 0) return null;
    var segment = path.substring(idx + marker.length);
    if (segment == 'add') return null;
    if (segment.endsWith('/models')) {
      segment = segment.substring(0, segment.length - '/models'.length);
    }
    if (segment.endsWith('/edit')) {
      segment = segment.substring(0, segment.length - '/edit'.length);
    }
    if (segment.isEmpty) return null;
    return Uri.decodeComponent(segment);
  }

  static bool _isLlmCliRoot(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.length == 2 && parts[0] == 'providers';
  }

  static String? _llmCliRootFromPath(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.length < 2 || parts[0] != 'providers') {
      return null;
    }
    return '/providers/${parts[1]}';
  }

  static bool _isTeamConfigDetail(String path) =>
      path.startsWith('/team-config/') && path.length > '/team-config/'.length;

  static bool _isSkillsDetail(String path) =>
      path.startsWith('/skills/') && path.length > '/skills/'.length;

  static bool _isMcpDetail(String path) =>
      path.startsWith('/mcp/') && path.length > '/mcp/'.length;

  static String? _memberTitle(BuildContext context, String path) {
    final id = path.split('/').last;
    final team = context.read<TeamCubit>().state.selectedTeam;
    if (team == null) return null;
    for (final member in team.members) {
      if (member.id == id) {
        final name = member.name.trim();
        return name.isEmpty ? context.l10n.memberName : name;
      }
    }
    return null;
  }
}
