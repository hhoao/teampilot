import 'dart:io';

import 'package:flutter/material.dart';

import 'strings.dart';

const _imageExtensions = {'png', 'jpg', 'jpeg', 'webp', 'gif'};
final _imageReferencePattern = RegExp(r'(?<!\S)@([^\s]+)');

@immutable
class AiUserMessageImage {
  const AiUserMessageImage({required this.path, required this.name});

  final String path;
  final String name;
}

@immutable
class AiUserMessageImageContent {
  const AiUserMessageImageContent({required this.images, required this.text});

  final List<AiUserMessageImage> images;
  final String text;

  bool get isNotEmpty => images.isNotEmpty;
}

AiUserMessageImageContent parseAiUserMessageImages(
  String text, {
  required String workspaceRoot,
  required bool usesPosixPaths,
}) {
  final matches = _imageReferencePattern.allMatches(text);
  final images = <AiUserMessageImage>[];
  final seen = <String>{};
  final visible = StringBuffer();
  var cursor = 0;
  for (final match in matches) {
    final reference = match.group(1)!;
    final extension = reference.split('.').last.toLowerCase();
    if (!_imageExtensions.contains(extension)) {
      continue;
    }
    final normalized = reference.replaceAll(r'\', '/');
    final absolute = _isAbsolutePath(normalized)
        ? normalized
        : [
            workspaceRoot.replaceAll(r'\', '/'),
            normalized,
          ].where((part) => part.isNotEmpty).join('/');
    if (absolute.isEmpty) continue;
    visible.write(text.substring(cursor, match.start));
    cursor = match.end;
    if (!seen.add(absolute)) continue;
    images.add(
      AiUserMessageImage(
        path: usesPosixPaths || !Platform.isWindows
            ? absolute
            : absolute.replaceAll('/', r'\'),
        name: normalized.split('/').last,
      ),
    );
  }
  if (images.isEmpty)
    return AiUserMessageImageContent(images: images, text: text);
  visible.write(text.substring(cursor));
  return AiUserMessageImageContent(
    images: images,
    text: visible.toString().trim(),
  );
}

bool _isAbsolutePath(String path) =>
    path.startsWith('/') ||
    RegExp(r'^[A-Za-z]:/').hasMatch(path) ||
    path.startsWith('//');

class AiUserMessageImages extends StatelessWidget {
  const AiUserMessageImages({required this.images, this.onOpen, super.key});

  final List<AiUserMessageImage> images;
  final ValueChanged<AiUserMessageImage>? onOpen;

  static const double _maxImageWidth = 280;
  static const double _maxImageHeight = 180;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = AiMessageStrings.of(context).imageAttachment;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final image in images)
          Semantics(
            image: true,
            button: onOpen != null,
            label: '$label: ${image.name}',
            child: Material(
              color: scheme.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: scheme.outlineVariant),
              ),
              child: InkWell(
                mouseCursor: onOpen == null
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.click,
                onTap: onOpen == null ? null : () => onOpen!(image),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _maxImageWidth,
                    maxHeight: _maxImageHeight,
                  ),
                  child: ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Image.file(
                      File(image.path),
                      fit: BoxFit.contain,
                      frameBuilder: (context, child, frame, synchronous) =>
                          frame == null
                          ? const SizedBox(width: 120, height: 80)
                          : child,
                      errorBuilder: (context, error, stackTrace) =>
                          _buildError(context, image, scheme),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildError(
    BuildContext context,
    AiUserMessageImage image,
    ColorScheme scheme,
  ) {
    return SizedBox(
      width: 220,
      height: 64,
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.broken_image_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              image.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}
