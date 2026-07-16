import 'file_icon_mapping.g.dart';

/// Resolved Material Icon Theme glyph for a file.
///
/// [iconName] maps to `assets/file_icons/$iconName.svg` (or `..._light.svg`
/// when [isLightVariant] is true and the runtime theme is light).
/// See `tool/sync_material_icons.dart` for the source mapping.
class FileIconInfo {
  const FileIconInfo(this.iconName, {this.isLightVariant = false});

  /// Icon name as used by VSCode Material Icon Theme, e.g. `dart`, `json`.
  final String iconName;

  /// Whether this file type has a designated light-theme variant
  /// (`{iconName}_light.svg`). The runtime widget decides whether to use it
  /// based on [ThemeData.brightness].
  final bool isLightVariant;
}

/// Material icon for a file name or path.
///
/// Match priority: exact file name (case-insensitive) > extension > default.
FileIconInfo fileIconForFileName(String name) {
  final baseName = name.split('/').last;
  final lower = baseName.toLowerCase();

  // 1. Exact file name (e.g. "pubspec.yaml", ".gitignore").
  final byName = kFileNameIcons[lower];
  if (byName != null) {
    return FileIconInfo(
      byName,
      isLightVariant: kLightFileNames.contains(lower),
    );
  }

  // 2. Extension.
  final ext = lower.contains('.') ? lower.split('.').last : '';
  final byExt = kFileExtensionIcons[ext];
  if (byExt != null) {
    return FileIconInfo(
      byExt,
      isLightVariant: kLightFileExtensions.contains(ext),
    );
  }

  // 3. Default.
  return const FileIconInfo(kDefaultFileIcon);
}
