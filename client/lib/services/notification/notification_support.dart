import 'dart:io';

/// Whether `flutter_local_notifications` can be initialized on this host.
///
/// The Windows backend activates WinRT toast APIs. Wine ships those APIs as a
/// stub that aborts the process instead of returning an error, so a Windows
/// build hosted by Wine has no notification backend and must not initialize
/// one. `wineboot.exe` is present only inside Wine prefixes, which makes it a
/// reliable marker without depending on environment variables that wrappers
/// such as Bottles do not forward.
bool detectOsNotificationSupport({bool? isWindows, bool? isWinePrefix}) {
  if (!(isWindows ?? Platform.isWindows)) return true;
  return !(isWinePrefix ?? _isWinePrefix());
}

bool _isWinePrefix() => File(r'C:\windows\system32\wineboot.exe').existsSync();
