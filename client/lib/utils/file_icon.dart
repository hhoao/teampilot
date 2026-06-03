import 'package:flutter/material.dart';

/// Material icon for a file name or path (extension-based).
IconData fileIconForFileName(String name) {
  final baseName = name.split('/').last;
  final ext = baseName.contains('.')
      ? baseName.split('.').last.toLowerCase()
      : '';
  switch (ext) {
    case 'dart':
      return Icons.code;
    case 'yaml':
    case 'yml':
    case 'json':
      return Icons.settings;
    case 'md':
      return Icons.description_outlined;
    case 'png':
    case 'jpg':
    case 'jpeg':
    case 'gif':
    case 'svg':
      return Icons.image_outlined;
    case 'zip':
    case 'tar':
    case 'gz':
      return Icons.archive_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}
