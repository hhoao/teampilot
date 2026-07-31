import 'dart:io';

import 'package:flutter/services.dart';

class TermuxPackageProbe {
  TermuxPackageProbe({
    MethodChannel? channel,
    bool? isAndroid,
  })  : _channel = channel ??
            const MethodChannel('com.hhoa.teampilot/packages'),
        _isAndroid = isAndroid;

  static const _termuxPackageName = 'com.termux';

  final MethodChannel _channel;

  /// Test override; defaults to [Platform.isAndroid].
  final bool? _isAndroid;

  Future<bool> isTermuxInstalled() async {
    final android = _isAndroid ?? Platform.isAndroid;
    if (!android) return false;
    try {
      final installed = await _channel.invokeMethod<bool>(
        'isPackageInstalled',
        {'packageName': _termuxPackageName},
      );
      return installed ?? false;
    } catch (_) {
      return false;
    }
  }
}
