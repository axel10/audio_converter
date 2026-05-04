library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import 'src/desktop_audio_converter.dart';
import 'src/models/audio_format.dart';
import 'src/models/convert_and_save_result.dart';
import 'src/models/convert_request.dart';
import 'src/models/convert_result.dart';
import 'src/models/converter_capabilities.dart';
export 'src/models/audio_format.dart';
export 'src/models/aac_encoder.dart';
export 'src/models/bit_rate_mode.dart';
export 'src/models/convert_and_save_result.dart';
export 'src/models/convert_request.dart';
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

  Future<ConvertResult> convertFile(ConvertRequest request) {
    return _desktopConverter.convertFile(request);
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

  Future<String?> pickOutputDirectory() async {
    if (Platform.isAndroid || Platform.isIOS) {
      return null;
    }
    return FilePicker.getDirectoryPath();
  }

  Future<ConvertAndSaveResult> convertAndSave(
    ConvertRequest request, {
    String? suggestedFileName,
  }) async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      final result = await convertFile(request);
      return ConvertAndSaveResult(
        conversionResult: result,
        savedPath: result.outputPath,
      );
    }

    final tempRequest = request.copyWith(
      outputPath: _buildTemporaryOutputPath(
        request.inputPath,
        request.outputFormat,
      ),
    );
    final baseName =
        suggestedFileName ??
        '${p.basenameWithoutExtension(request.inputPath)}.${request.outputFormat.value}';
    final result = await convertFile(tempRequest);
    if (!result.success) {
      return ConvertAndSaveResult(conversionResult: result);
    }

    final tempPath = result.outputPath ?? tempRequest.outputPath;
    final tempFile = File(tempPath);
    if (!await tempFile.exists()) {
      return ConvertAndSaveResult(
        conversionResult: result.copyWith(
          success: false,
          errorCode: 'temporary_output_missing',
          errorMessage: 'Temporary output file was not found.',
        ),
        temporaryPath: tempPath,
      );
    }

    final bytes = await tempFile.readAsBytes();
    final savedPath = await FilePicker.saveFile(
      fileName: baseName,
      type: FileType.custom,
      allowedExtensions: <String>[request.outputFormat.value],
      bytes: bytes,
    );

    try {
      await tempFile.delete();
    } catch (_) {
      // Best-effort cleanup only.
    }

    return ConvertAndSaveResult(
      conversionResult: result,
      savedPath: savedPath,
      temporaryPath: tempPath,
      saveCancelled: savedPath == null,
    );
  }

  String _buildTemporaryOutputPath(String inputPath, AudioFormat outputFormat) {
    final baseName = p.basenameWithoutExtension(inputPath);
    final tempDir = Directory(
      p.join(Directory.systemTemp.path, 'audio_converter'),
    );
    return p.join(tempDir.path, '$baseName.${outputFormat.value}');
  }
}
