library;

import 'package:file_picker/file_picker.dart';

import 'src/desktop_audio_converter.dart';
import 'src/models/convert_and_save_result.dart';
import 'src/models/convert_request.dart';
import 'src/models/conversion_progress.dart';
import 'src/models/convert_result.dart';
import 'src/models/converter_capabilities.dart';
export 'src/models/audio_format.dart';
export 'src/models/aac_encoder.dart';
export 'src/models/bit_rate_mode.dart';
export 'src/models/convert_and_save_result.dart';
export 'src/models/convert_request.dart';
export 'src/models/conversion_progress.dart';
export 'src/models/convert_result.dart';
export 'src/models/converter_capabilities.dart';
export 'src/rust/api/simple.dart';
export 'src/rust/frb_generated.dart' show RustLib;

class AudioConverter {
  AudioConverter({DesktopAudioConverter? desktopConverter})
    : _desktopConverter = desktopConverter ?? DesktopAudioConverter();

  final DesktopAudioConverter _desktopConverter;

  Future<ConverterCapabilities> getCapabilities() {
    return _desktopConverter.getCapabilities();
  }

  Future<ConvertResult> convertFile(
    ConvertRequest request, {
    AudioConverterProgressCallback? onProgress,
  }) {
    return _desktopConverter.convertFile(request, onProgress: onProgress);
  }

  Future<List<ConvertResult>> convertFiles(
    List<ConvertRequest> requests, {
    AudioConverterProgressCallback? onProgress,
  }) {
    return _desktopConverter.convertFiles(requests, onProgress: onProgress);
  }

  Future<String?> pickInputFile({List<String>? allowedExtensions}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          allowedExtensions ??
          <String>[
            'aac',
            'aif',
            'aiff',
            'caf',
            'flac',
            'm4a',
            'm4b',
            'mp3',
            'ogg',
            'opus',
            'wav',
          ],
      allowMultiple: false,
      withData: false,
    );
    return result?.files.single.path;
  }

  Future<List<String>> pickInputFiles({List<String>? allowedExtensions}) async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions:
          allowedExtensions ??
          <String>[
            'aac',
            'aif',
            'aiff',
            'caf',
            'flac',
            'm4a',
            'm4b',
            'mp3',
            'ogg',
            'opus',
            'wav',
          ],
      allowMultiple: true,
      withData: false,
    );
    if (result == null) {
      return const <String>[];
    }

    return result.paths.whereType<String>().toList(growable: false);
  }

  Future<String?> pickOutputDirectory() async {
    return FilePicker.getDirectoryPath();
  }

  Future<ConvertAndSaveResult> convertAndSave(ConvertRequest request) async {
    final result = await convertFile(request);
    return ConvertAndSaveResult(
      conversionResult: result,
      savedPath: result.outputPath,
      temporaryPath: result.outputPath,
      saveCancelled: false,
    );
  }
}
