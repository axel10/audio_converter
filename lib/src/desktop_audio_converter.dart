import 'dart:convert';
import 'dart:io';

import 'models/audio_format.dart';
import 'models/convert_request.dart';
import 'models/conversion_progress.dart';
import 'models/convert_result.dart';
import 'models/converter_capabilities.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'rust/frb_generated.dart';
import 'rust/api/simple.dart' as rust_api;

class DesktopAudioConverter {
  static Future<void>? _rustInitFuture;

  bool get _usesBundledRustFfmpeg =>
      Platform.isAndroid ||
      Platform.isIOS ||
      Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux;

  bool get _usesProcessLoadedRust => Platform.isIOS || Platform.isMacOS;

  Future<void> _ensureRustInitialized() {
    if (!_usesBundledRustFfmpeg) {
      return Future<void>.value();
    }

    _rustInitFuture ??= _initRust();
    return _rustInitFuture!;
  }

  Future<void> _initRust() async {
    try {
      await RustLib.init(
        forceSameCodegenVersion: false,
        externalLibrary: _usesProcessLoadedRust
            ? ExternalLibrary.process(
                iKnowHowToUseIt: true,
                debugInfo: Platform.isIOS
                    ? 'for iOS Runner.debug.dylib'
                    : 'for macOS Runner.debug.dylib',
              )
            : null,
      );
    } catch (error) {
      _rustInitFuture = null;
      throw StateError(
        'FFmpeg runtime libraries are missing or could not be loaded. '
        'Please add the audio_ffmpeg_lib dependency and make sure its ffmpeg '
        'assets have been built or downloaded. Original error: $error',
      );
    }
  }

  Future<ConvertResult> convertFile(
    ConvertRequest request, {
    AudioConverterProgressCallback? onProgress,
  }) async {
    if (_usesBundledRustFfmpeg) {
      await _ensureRustInitialized();
      return _convertWithRustFfmpeg(request, onProgress: onProgress);
    }
    return const ConvertResult(
      success: false,
      errorCode: 'unsupported_platform',
      errorMessage:
          'Audio converter is only available on Android, iOS, macOS, Windows, and Linux.',
    );
  }

  Future<List<ConvertResult>> convertFiles(
    List<ConvertRequest> requests, {
    AudioConverterProgressCallback? onProgress,
  }) async {
    final results = <ConvertResult>[];
    for (var index = 0; index < requests.length; index++) {
      final request = requests[index];
      final completedBefore = index;

      onProgress?.call(
        ConversionProgress(
          completedFiles: completedBefore,
          totalFiles: requests.length,
          currentFilePath: request.inputPath,
          currentFileProgress: 0,
          message: 'Starting ${index + 1}/${requests.length}',
        ),
      );

      final result = await convertFile(
        request,
        onProgress: (progress) {
          onProgress?.call(
            progress.copyWith(
              completedFiles: completedBefore,
              totalFiles: requests.length,
            ),
          );
        },
      );
      results.add(result);

      onProgress?.call(
        ConversionProgress(
          // Keep completedFiles anchored to the file that just finished.
          // This preserves the batch fraction: after file 1 of 4 completes,
          // overall progress should be 1/4, not 2/4.
          completedFiles: completedBefore,
          totalFiles: requests.length,
          currentFilePath: request.inputPath,
          currentFileProgress: 1,
          message: result.success
              ? 'Completed ${index + 1}/${requests.length}'
              : 'Failed ${index + 1}/${requests.length}',
        ),
      );
    }
    return results;
  }

  Future<ConverterCapabilities> getCapabilities() async {
    if (_usesBundledRustFfmpeg) {
      await _ensureRustInitialized();
      final raw = rust_api.getCapabilities();
      final capabilities = ConverterCapabilities.fromMap(
        jsonDecode(raw) as Map<Object?, Object?>,
      );
      return capabilities;
    }

    return const ConverterCapabilities(
      engine: 'unsupported',
      supportedOutputFormats: <AudioFormat>[],
      supportsProgress: false,
      supportsCancellation: false,
      requiresExternalBinary: false,
    );
  }

  Future<ConvertResult> _convertWithRustFfmpeg(
    ConvertRequest request, {
    AudioConverterProgressCallback? onProgress,
  }) async {
    final rawEvents = rust_api.convertFileWithProgress(
      requestJson: jsonEncode(request.toMap()),
    );
    ConvertResult? result;

    await for (final rawEvent in rawEvents) {
      final event = jsonDecode(rawEvent);
      if (event is! Map) {
        continue;
      }

      switch (event['kind']?.toString()) {
        case 'progress':
          final progress = _progressFromRustEvent(
            event,
            fallbackPath: request.inputPath,
          );
          onProgress?.call(progress);
          break;
        case 'result':
          final rawResult = event['result'];
          if (rawResult is Map) {
            result = ConvertResult.fromMap(rawResult.cast<Object?, Object?>());
          }
          break;
      }
    }

    if (result == null) {
      throw StateError('Rust progress stream ended without a final result.');
    }

    return result;
  }

  ConversionProgress _progressFromRustEvent(
    Map event, {
    required String fallbackPath,
  }) {
    final currentPositionUs =
        event['currentPositionUs'] ?? event['current_position_us'];
    final totalDurationUs =
        event['totalDurationUs'] ?? event['total_duration_us'];
    return ConversionProgress(
      completedFiles:
          (event['completedFiles'] ?? event['completed_files']) as int? ?? 0,
      totalFiles: (event['totalFiles'] ?? event['total_files']) as int? ?? 1,
      currentFilePath:
          (event['currentFilePath'] ?? event['current_file_path']) as String? ??
          fallbackPath,
      currentFileProgress:
          ((event['currentFileProgress'] ?? event['current_file_progress'])
                  as num?)
              ?.toDouble(),
      currentPosition: currentPositionUs is num
          ? Duration(microseconds: currentPositionUs.toInt())
          : null,
      totalDuration: totalDurationUs is num
          ? Duration(microseconds: totalDurationUs.toInt())
          : null,
      message: event['message'] as String?,
    );
  }
}
