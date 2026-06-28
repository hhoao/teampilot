import Cocoa
import FlutterMacOS
import native_splash_screen_macos

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationWillFinishLaunching(_ notification: Notification) {
    NativeSplashScreen.configurationProvider = NativeSplashScreenConfiguration()
    NativeSplashScreen.show()
  }
}
