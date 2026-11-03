@Tags(['integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/cli/qoder/provider/qoder_models_service.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

void main() {
  test('probes the real qodercli ACP model catalog', () async {
    final home = Platform.environment['HOME'] ?? '';
    final auth = Directory('$home/.qoder/.auth');
    final which = await Process.run('which', ['qodercli']);
    if (which.exitCode != 0 || !auth.existsSync()) {
      // ignore: avoid_print
      print('[qoder-models] skipped: qodercli or ~/.qoder/.auth is missing');
      return;
    }

    final temp = Directory.systemTemp.createTempSync('qoder-models-');
    final service = QoderModelsService(
      fs: LocalFilesystem(),
      basePath: temp.path,
      machineHome: home,
    );
    try {
      await service.ensureLoaded(providerId: '');
      final models = service.modelIdsFor(providerId: '');
      // ignore: avoid_print
      print('[qoder-models] ${models.join(', ')}');
      expect(models, isNotEmpty);
      expect(models, contains('auto'));
    } finally {
      try {
        temp.deleteSync(recursive: true);
      } on FileSystemException {
        // Best effort cleanup.
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
