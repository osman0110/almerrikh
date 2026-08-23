class AssessmentVideoService {
  Future<void> start(String assessmentId) async {}
  void addFrame(dynamic rawFrame) {}
  Future<String?> finish() async => null;
  Future<void> discard() async {}

  static Future<void> deleteFolder(String path) async {}
  static Future<List<String>> listFrames(String path) async => [];
}
