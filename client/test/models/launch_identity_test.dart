import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_identity.dart';

void main() {
  test('encode/decode a bare identity id', () {
    const li = LaunchIdentity('coding');
    expect(li.encode(), 'coding');
    expect(LaunchIdentity.decode('coding'), li);
  });

  test('decode trims and rejects empty', () {
    expect(LaunchIdentity.decode('  squad '), const LaunchIdentity('squad'));
    expect(LaunchIdentity.decode(''), isNull);
    expect(LaunchIdentity.decode(null), isNull);
  });
}
