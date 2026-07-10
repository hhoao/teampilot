import 'config_bundle.dart';
import 'launch_profile_kind.dart';
import 'workspace_icon_ref.dart';

/// A named, reusable launch identity. A directory ([Workspace]) is *where*
/// work happens; a [LaunchProfile] is *who/how* — the CLI config bundle a
/// session launches with.
///
/// Only [TeamProfile] implements this. Simple (unteamed) launch is a session
/// mode, not a profile kind.
abstract class LaunchProfile {
  String get id;
  LaunchProfileKind get kind;
  String get display;
  WorkspaceIconRef get icon;
  ConfigBundle get bundle;

  /// Serializes the concrete record for persistence by `LaunchProfileRepository`.
  Map<String, Object?> toJson();
}
