import '../../support/post_frame_test_harness.dart';
import '../../support/rust_lib_test_init.dart';
import 'integration_prerequisites.dart';

/// Standard setUp/tearDown for ChatCubit + AppStorage integration tests.
Future<void> setUpIntegrationAppStorage() async {
  IntegrationPrerequisites.resetHttpOverrides();
  await initRustLibForTests();
  setUpTestAppStorage();
}

void tearDownIntegrationAppStorage() => tearDownTestAppStorage();
