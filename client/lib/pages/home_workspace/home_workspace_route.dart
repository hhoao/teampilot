import '../../models/launch_profile_ref.dart';
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

  static LaunchProfileRef? identity(String location) =>
      LaunchProfileRef.decode(parse(location).queryParameters['as']);

  static String? view(String location) => parse(location).queryParameters['view'];

  static TeamConfigSection? homeTeamSection(String location) =>
      TeamConfigSection.fromSegment(parse(location).queryParameters['section']);

  static String? homeMemberId(String location) =>
      parse(location).queryParameters['member'];

  static HomeGlobalView? homeGlobalView(String location) =>
      HomeGlobalView.fromSegment(
        parse(location).queryParameters[HomeGlobalView.globalQueryParam],
      );

  static WorkspaceConfigSection? workspaceConfigSection(String location) =>
      WorkspaceConfigSection.fromSegment(
        parse(location).queryParameters['section'],
      );
}
