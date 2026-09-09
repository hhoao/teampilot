import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import 'home_ssh_profile_impact.dart';

/// Applies [HomeSshProfileImpact] to the home storage plane.
///
/// Single place that may reinstall the home storage plane / reload workspace
/// index after SSH catalog changes. [SshProfileCubit] must not call this
/// directly.
class HomeStorageInvalidator {
  HomeStorageInvalidator({
    required String Function() homeTargetId,
    Future<void> Function()? reinstallAndReload,
    required Future<void> Function(String id) switchHome,
    this.fallbackHomeId = RuntimeTarget.localId,
  }) : _homeTargetId = homeTargetId,
       _reinstallAndReload = reinstallAndReload,
       _switchHome = switchHome;

  final String Function() _homeTargetId;
  final Future<void> Function()? _reinstallAndReload;
  final Future<void> Function(String id) _switchHome;
  final String fallbackHomeId;

  /// Impact of a catalog diff for the current home target.
  ///
  /// Pure classification — callers map [HomeSshProfileImpact] to their own
  /// reload/switch side effects. [applyProfilesChanged] bundles both using the
  /// injected callbacks.
  HomeSshProfileImpact impactOf({
    required List<SshProfile> previous,
    required List<SshProfile> next,
  }) {
    return resolveHomeSshProfileImpact(
      homeTargetId: _homeTargetId(),
      previous: previous,
      next: next,
    );
  }

  Future<void> applyProfilesChanged({
    required List<SshProfile> previous,
    required List<SshProfile> next,
  }) async {
    switch (impactOf(previous: previous, next: next)) {
      case HomeSshProfileImpact.none:
        return;
      case HomeSshProfileImpact.homeConnectionChanged:
        await _reinstallAndReload?.call();
      case HomeSshProfileImpact.homeProfileMissing:
        await _switchHome(fallbackHomeId);
    }
  }
}
