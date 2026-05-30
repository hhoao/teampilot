import '../cli_capability.dart';

abstract interface class TranscriptProbeCapability implements CliCapability {
  bool get probeHistoryFiles;
}
