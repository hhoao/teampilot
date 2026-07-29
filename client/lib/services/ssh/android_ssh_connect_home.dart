/// Android Connect side-effect: switch home to the connected profile, then
/// persist the selected profile id (existing cubit path).
Future<void> applyAndroidSshConnectHome({
  required String profileId,
  required Future<void> Function(String homeId) selectHome,
  required Future<void> Function(String profileId) selectProfile,
}) async {
  await selectHome('ssh:$profileId');
  await selectProfile(profileId);
}
