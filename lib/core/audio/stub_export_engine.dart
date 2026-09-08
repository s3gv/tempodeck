import 'i_export_engine.dart';

class StubExportEngine implements IExportEngine {
  @override
  int estimateFileSizeBytes({
    required Duration duration,
    int bitrateBps = 192000,
  }) {
    return (bitrateBps / 8 * duration.inSeconds).round();
  }

  @override
  Stream<double> exportToMp3({
    required ExportSource source,
    required String outputPath,
    int bitrateBps = 192000,
    ExportMp3Layout layout = ExportMp3Layout.singleFile,
    ExportContentOptions contentOptions = const ExportContentOptions(),
    void Function(List<String> warnings)? onWarnings,
  }) async* {
    yield 1.0;
  }
}
