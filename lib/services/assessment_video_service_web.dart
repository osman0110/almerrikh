/// Web has no local filesystem to stash review frames on, and the raw
/// [CameraFrame.image] is always null there (inference reads the DOM video
/// element directly) — so this is a no-op stand-in with the same API.
class AssessmentVideoService {
  Future<void> start(String assessmentId) async {}
  void addFrame(dynamic rawFrame) {}
  Future<String?> finish() async => null;
  Future<void> discard() async {}

  static Future<void> deleteFolder(String path) async {}
  static Future<List<String>> listFrames(String path) async => [];
}
