import '../../support/post_frame_test_harness.dart';
import 'integration_prerequisites.dart';

/// Standard setUp/tearDown for ChatCubit + AppStorage integration tests.
void setUpIntegrationAppStorage() {
  IntegrationPrerequisites.resetHttpOverrides();
  setUpTestAppStorage();
}

void tearDownIntegrationAppStorage() => tearDownTestAppStorage();
