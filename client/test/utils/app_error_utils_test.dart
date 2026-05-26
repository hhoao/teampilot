import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:teampilot/utils/app_error_utils.dart';

void main() {
  group('AppErrorUtils.classify', () {
    test('network socket errors are not reported', () {
      final decision = AppErrorUtils.classify(
        const SocketException('Connection refused'),
      );
      expect(decision.kind, AppErrorKind.network);
      expect(decision.shouldReport, isFalse);
      expect(decision.shouldNotifyUser, isTrue);
    });

    test('storage errors are not reported', () {
      final decision = AppErrorUtils.classify(
        const FileSystemException('No space left on device'),
      );
      expect(decision.kind, AppErrorKind.storage);
      expect(decision.shouldReport, isFalse);
    });

    test('unknown errors are reported', () {
      final decision = AppErrorUtils.classify(StateError('boom'));
      expect(decision.kind, AppErrorKind.unexpected);
      expect(decision.shouldReport, isTrue);
    });

    test('http client errors are treated as network', () {
      final decision = AppErrorUtils.classify(
        http.ClientException('Failed host lookup'),
      );
      expect(decision.kind, AppErrorKind.network);
      expect(decision.shouldReport, isFalse);
    });
  });
}
