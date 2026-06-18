import 'config_bundle.dart';
import 'identity_kind.dart';
import 'project_icon_ref.dart';

/// A named, reusable launch identity. A directory ([AppProject]) is *where*
/// work happens; a [WorkspaceIdentity] is *who/how* — the CLI config bundle a
/// session launches with. Subtypes: [PersonalIdentity] or [TeamIdentity].
abstract class WorkspaceIdentity {
  String get id;
  IdentityKind get kind;
  String get display;
  ProjectIconRef get icon;
  ConfigBundle get bundle;
}
