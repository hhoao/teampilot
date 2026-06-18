import 'config_bundle.dart';
import 'launch_profile_kind.dart';
import 'workspace_icon_ref.dart';

/// A named, reusable launch identity. A directory ([Workspace]) is *where*
/// work happens; a [LaunchProfile] is *who/how* — the CLI config bundle a
/// session launches with. Subtypes: [PersonalProfile] or [TeamProfile].
///
/// Not `sealed` because the subtypes live in separate libraries; callers that
/// need to discriminate switch on [kind] (an exhaustive enum) rather than the
/// runtime type.
abstract class LaunchProfile {
  String get id;
  LaunchProfileKind get kind;
  String get display;
  WorkspaceIconRef get icon;
  ConfigBundle get bundle;

  /// Serializes the concrete record for persistence by `LaunchProfileRepository`.
  Map<String, Object?> toJson();
}
