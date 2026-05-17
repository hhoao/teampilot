/// How the app runs [flashskyai]: on this device ([localPty]) or on a remote
/// host over SSH ([ssh]).
enum ConnectionMode {
  localPty,
  ssh,
}

extension ConnectionModeJson on ConnectionMode {
  String toJson() => name;

  static ConnectionMode fromJson(String? raw, {ConnectionMode? fallback}) {
    if (raw == ConnectionMode.ssh.name) return ConnectionMode.ssh;
    if (raw == ConnectionMode.localPty.name) return ConnectionMode.localPty;
    return fallback ?? ConnectionMode.localPty;
  }
}
