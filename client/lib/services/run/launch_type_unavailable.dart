import '../../l10n/app_localizations.dart';
import '../../models/workspace_folder.dart';
import 'launch_type_registry.dart';

/// Stable reason codes for [LaunchTypeRegistry] unavailability (localized in UI).
abstract final class LaunchTypeUnavailableCodes {
  static const unknown = 'runTypeUnknown';
  static const remote = 'runTypeUnavailableRemote';
  static const local = 'runTypeUnavailable';
}

/// Maps a registry reason code + type name to a localized tooltip/message.
String? localizeLaunchTypeUnavailable(
  AppLocalizations l10n,
  String? code, {
  required String type,
}) {
  if (code == null || code.isEmpty) return null;
  return switch (code) {
    LaunchTypeUnavailableCodes.unknown => l10n.runTypeUnknown(type),
    LaunchTypeUnavailableCodes.remote => l10n.runTypeUnavailableRemote(type),
    LaunchTypeUnavailableCodes.local => l10n.runTypeUnavailable(type),
    _ => code,
  };
}

/// Reason code when [type] cannot run on [targetId], or null when available.
String? launchTypeUnavailableCode(
  LaunchTypeRegistry registry, {
  required String type,
  required String targetId,
}) {
  if (registry.isAvailable(type, targetId: targetId)) return null;
  final contribution = registry.get(type);
  if (contribution == null) return LaunchTypeUnavailableCodes.unknown;
  if (targetId != WorkspaceFolder.localTargetId) {
    return LaunchTypeUnavailableCodes.remote;
  }
  return LaunchTypeUnavailableCodes.local;
}
