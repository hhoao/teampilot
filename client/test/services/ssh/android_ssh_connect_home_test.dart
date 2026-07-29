import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/android_ssh_connect_home.dart';

void main() {
  test('selects home ssh:id then selectProfile', () async {
    final calls = <String>[];
    await applyAndroidSshConnectHome(
      profileId: 'p1',
      selectHome: (id) async => calls.add('home:$id'),
      selectProfile: (id) async => calls.add('profile:$id'),
    );
    expect(calls, ['home:ssh:p1', 'profile:p1']);
  });
}
