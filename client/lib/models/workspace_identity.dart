import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_icon_ref.dart';

/// A named, reusable launch identity. A directory ([AppProject]) is *where*
/// work happens; a [Identity] is *who/how* — the CLI config bundle a
/// session launches with. Subtypes: [PersonalIdentity] or [TeamIdentity].
///
/// Not `sealed` because the subtypes live in separate libraries; callers that
/// need to discriminate switch on [kind] (an exhaustive enum) rather than the
/// runtime type.
abstract class Identity {
  String get id;
  IdentityKind get kind;
  String get display;
  ProjectIconRef get icon;
  ConfigBundle get bundle;

  /// Serializes the concrete record for persistence by `IdentityRepository`.
  Map<String, Object?> toJson();
}
