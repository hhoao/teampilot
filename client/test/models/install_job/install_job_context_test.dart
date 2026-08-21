import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';

void main() {
  test('requestCancel sets isCancelled', () {
    final ctx = InstallJobContext();
    expect(ctx.isCancelled, isFalse);
    ctx.requestCancel();
    expect(ctx.isCancelled, isTrue);
  });
}
