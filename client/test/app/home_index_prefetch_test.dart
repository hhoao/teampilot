import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/app/home_index_prefetch.dart';

void main() {
  test(
    'remote home does not await a hung native-path isolate prefetch',
    () async {
      final native = Completer<void>().future;
      var boundStarted = false;
      final selected = bindHomeIndexPrefetch(
        isRemoteWorkPlane: true,
        nativePathPrefetch: native,
        boundHomePrefetch: () async {
          boundStarted = true;
        },
      );

      await selected.timeout(const Duration(milliseconds: 200));
      expect(boundStarted, isTrue);
    },
  );

  test('local home awaits the native-path prefetch when provided', () async {
    final native = Completer<void>();
    var boundStarted = false;
    final selected = bindHomeIndexPrefetch(
      isRemoteWorkPlane: false,
      nativePathPrefetch: native.future,
      boundHomePrefetch: () async {
        boundStarted = true;
      },
    );

    native.complete();
    await selected.timeout(const Duration(milliseconds: 200));
    expect(boundStarted, isFalse);
  });
}
