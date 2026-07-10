import '../team_config/team_config_section.dart';
import 'home_workspace_global_section.dart';
import 'workspace/workspace_config_section.dart';

/// Parses `/home-v2` and `/home-v2/workspace/:id` locations for [HomeShell].
abstract final class HomeWorkspaceRoute {
  static Uri parse(String location) {
    if (location.startsWith('http://') || location.startsWith('https://')) {
      return Uri.parse(location);
    }
    return Uri.parse('http://local$location');
  }

  static String? workspaceId(String location) {
    final uri = parse(location);
    final segments = uri.pathSegments;
    if (segments.length >= 3 &&
        segments[0] == 'home-v2' &&
        segments[1] == 'workspace') {
      return segments[2];
    }
    return null;
  }

  static String? view(String location) =>
      parse(location).queryParameters['view'];

  /// Manage / landing profile id (`personal` or team id).
  static String? profile(String location) {
    final raw = parse(location).queryParameters['profile']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  static TeamConfigSection? homeTeamSection(String location) =>
      TeamConfigSection.fromSegment(parse(location).queryParameters['section']);

  static String? homeMemberId(String location) =>
      parse(location).queryParameters['member'];

  /// Expert Hub member key for compose-landing summon (`?expert=`).
  static String? expert(String location) {
    final raw = parse(location).queryParameters['expert']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// Session id for workbench deep-link (`?session=`).
  static String? session(String location) {
    final raw = parse(location).queryParameters['session']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// `/home-v2/workspace/:id?session=:sessionId` — opens a session from OS
  /// notification taps (and other deep links).
  static String sessionLocation({
    required String workspaceId,
    required String sessionId,
  }) => Uri(
    path: '/home-v2/workspace/$workspaceId',
    queryParameters: {'session': sessionId},
  ).toString();

  /// Same path/query as [location] with `session` removed (avoids re-open loops).
  static String locationWithoutSession(String location) {
    final uri = parse(location);
    final params = Map<String, String>.from(uri.queryParameters)
      ..remove('session');
    return Uri(
      path: uri.path,
      queryParameters: params.isEmpty ? null : params,
    ).toString();
  }

  static HomeGlobalView? homeGlobalView(String location) =>
      HomeGlobalView.fromSegment(
        parse(location).queryParameters[HomeGlobalView.globalQueryParam],
      );

  /// Expert Hub member key when [homeGlobalView] is [HomeGlobalView.expertHub].
  static String? expertHubMemberKey(String location) {
    if (homeGlobalView(location) != HomeGlobalView.expertHub) return null;
    final raw = parse(location).queryParameters['member']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// My Experts member key when [homeGlobalView] is [HomeGlobalView.myExperts].
  static String? myExpertsMemberKey(String location) {
    if (homeGlobalView(location) != HomeGlobalView.myExperts) return null;
    final raw = parse(location).queryParameters['member']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// Team Hub team key when [homeGlobalView] is [HomeGlobalView.teamHub].
  static String? teamHubTeamKey(String location) {
    if (homeGlobalView(location) != HomeGlobalView.teamHub) return null;
    final raw = parse(location).queryParameters['team']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// My Teams team id when [homeGlobalView] is [HomeGlobalView.myTeams].
  static String? myTeamsTeamId(String location) {
    if (homeGlobalView(location) != HomeGlobalView.myTeams) return null;
    final raw = parse(location).queryParameters['team']?.trim() ?? '';
    return raw.isEmpty ? null : raw;
  }

  /// `/home-v2?global=expertHub&member=<key>` — opens Expert Hub detail.
  static String expertHubMemberLocation(String memberKey) => Uri(
    path: '/home-v2',
    queryParameters: {
      HomeGlobalView.globalQueryParam: HomeGlobalView.expertHub.routeSegment,
      'member': memberKey,
    },
  ).toString();

  /// `/home-v2?global=teamHub&team=<key>` — opens Team Hub detail.
  static String teamHubTeamLocation(String teamKey) => Uri(
    path: '/home-v2',
    queryParameters: {
      HomeGlobalView.globalQueryParam: HomeGlobalView.teamHub.routeSegment,
      'team': teamKey,
    },
  ).toString();

  static WorkspaceConfigSection? workspaceConfigSection(String location) =>
      WorkspaceConfigSection.fromSegment(
        parse(location).queryParameters['section'],
      );
}
