import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/usage/usage_format.dart';

void main() {
  test('usageChartLabelStride keeps about seven bottom labels', () {
    expect(usageChartLabelStride(0), 1);
    expect(usageChartLabelStride(1), 1);
    expect(usageChartLabelStride(7), 1);
    expect(usageChartLabelStride(14), 2);
    expect(usageChartLabelStride(30), 5);
  });
}
