import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/file_icon.dart';

/// Renders a colored Material Icon Theme SVG for [fileName].
///
/// Uses `flutter_svg` (already a dependency). The SVG's internal `fill` colors
/// are preserved, so each file type shows its designated color. When the
/// runtime theme is light and the file type has a light variant, the
/// `{iconName}_light.svg` asset is used instead.
class FileIconWidget extends StatelessWidget {
  const FileIconWidget({
    required this.fileName,
    this.size = 16,
    super.key,
  });

  final String fileName;
  final double size;

  static const _assetDir = 'assets/file_icons';

  @override
  Widget build(BuildContext context) {
    final info = fileIconForFileName(fileName);
    final useLight = Theme.of(context).brightness == Brightness.light &&
        info.isLightVariant;
    final suffix = useLight ? '_light' : '';
    final path = '$_assetDir/${info.iconName}$suffix.svg';
    return SvgPicture.asset(
      path,
      width: size,
      height: size,
    );
  }
}
