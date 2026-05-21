/// Where TeamPilot stores teams/skills/projects on Windows desktop.
enum WindowsStorageBackend {
  /// `%AppData%/com.hhoa.teampilot` via [LocalFilesystem].
  native,

  /// WSL `$HOME/.local/share/com.hhoa.teampilot` via [WslFilesystem].
  wsl,
}

extension WindowsStorageBackendJson on WindowsStorageBackend {
  String toJson() => name;

  static WindowsStorageBackend fromJson(String? raw) {
    if (raw == WindowsStorageBackend.wsl.name) {
      return WindowsStorageBackend.wsl;
    }
    return WindowsStorageBackend.native;
  }
}
