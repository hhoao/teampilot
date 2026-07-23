import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/resource_manager/resource_memory_format.dart';

void main() {
  test('formats bytes as MB with one decimal', () {
    expect(formatResourceMemory(960.8 * 1024 * 1024), '960.8 MB');
  });

  test('null memory formats as em dash', () {
    expect(formatResourceMemory(null), '—');
  });

  test('null cpu formats as em dash', () {
    expect(formatResourceCpu(null), '—');
  });

  test('formats cpu as percent with one decimal', () {
    expect(formatResourceCpu(1.5), '1.5%');
  });
}
