import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/storage/app_paths.dart';

void main() {
  test('attention paths are stable and epoch-scoped', () {
    const paths = AppPaths('/tp');

    expect(
      paths.attentionLogJsonForEpoch(7),
      '/tp/attention/log-7.jsonl',
    );
    expect(paths.attentionCursorsJson, '/tp/attention/cursors.json');
  });
}
