import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models/audio_format.dart';
import 'models/aac_encoder.dart';
import 'models/bit_rate_mode.dart';
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
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  bool get _usesProcessLoadedRust => Platform.isIOS || Platform.isMacOS;

  Future<void> _ensureRustInitialized() {
    if (!_usesBundledRustFfmpeg) {
      return Future<void>.value();
    }

    _rustInitFuture ??= RustLib.init(
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
    return _rustInitFuture!;
  }

  Future<ConvertResult> convertFile(
    ConvertRequest request, {
    AudioConverterProgressCallback? onProgress,
  }) async {
    if (_usesBundledRustFfmpeg) {
      await _ensureRustInitialized();
      return _convertWithRustFfmpeg(request, onProgress: onProgress);
    }
    if (Platform.isWindows || Platform.isLinux) {
      return _convertWithFfmpeg(request, onProgress: onProgress);
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

    if (Platform.isWindows || Platform.isLinux) {
      return const ConverterCapabilities(
        engine: 'ffmpeg',
        supportedOutputFormats: <AudioFormat>[
          AudioFormat.aac,
          AudioFormat.alac,
          AudioFormat.aiff,
          AudioFormat.caf,
          AudioFormat.flac,
          AudioFormat.m4a,
          AudioFormat.m4b,
          AudioFormat.mp3,
          AudioFormat.ogg,
          AudioFormat.opus,
          AudioFormat.wav,
        ],
        supportsProgress: true,
        supportsCancellation: false,
        requiresExternalBinary: true,
        supportedAacEncoders: <AacEncoder>[
          AacEncoder.fdkaac,
          AacEncoder.builtinAac,
        ],
        notes:
            'Uses a user-provided ffmpeg binary or one available on PATH. Live progress is reported through ffmpeg/ffprobe when available.',
      );
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

  Future<ConvertResult> _convertWithFfmpeg(
    ConvertRequest request, {
    AudioConverterProgressCallback? onProgress,
  }) async {
    final ffmpegPath = request.ffmpegPath?.trim().isNotEmpty == true
        ? request.ffmpegPath!.trim()
        : _defaultBundledFfmpegPath() ?? 'ffmpeg';
    final args = <String>[
      '-y',
      '-i',
      request.inputPath,
      ..._ffmpegArgs(request),
      ...?request.customArgs,
      '-progress',
      'pipe:1',
      '-nostats',
      request.outputPath,
    ];

    final duration = await _probeDuration(
      request.inputPath,
      customFfprobePath: request.ffmpegPath,
    );

    onProgress?.call(
      ConversionProgress(
        completedFiles: 0,
        totalFiles: 1,
        currentFilePath: request.inputPath,
        currentFileProgress: 0,
        currentPosition: Duration.zero,
        totalDuration: duration,
        message: 'Starting conversion',
      ),
    );

    final process = await Process.start(ffmpegPath, args, runInShell: false);

    final stdoutLines = <String>[];
    final stderrLines = <String>[];
    var progressState = <String, String>{};
    var lastReportedProgress = -1.0;

    Future<void> drainStdout() async {
      await for (final line
          in process.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          continue;
        }

        stdoutLines.add(trimmed);
        if (trimmed.contains('=')) {
          final separatorIndex = trimmed.indexOf('=');
          final key = trimmed.substring(0, separatorIndex).trim();
          final value = trimmed.substring(separatorIndex + 1).trim();
          progressState[key] = value;

          if (key == 'progress') {
            final currentPosition = _durationFromProgressState(progressState);
            final reportProgress = _progressFraction(
              currentPosition: currentPosition,
              totalDuration: duration,
            );
            if (reportProgress != null &&
                (reportProgress - lastReportedProgress).abs() >= 0.005) {
              lastReportedProgress = reportProgress;
              onProgress?.call(
                ConversionProgress(
                  completedFiles: 0,
                  totalFiles: 1,
                  currentFilePath: request.inputPath,
                  currentFileProgress: reportProgress,
                  currentPosition: currentPosition,
                  totalDuration: duration,
                  message: 'Converting',
                ),
              );
            } else if (currentPosition != null) {
              onProgress?.call(
                ConversionProgress(
                  completedFiles: 0,
                  totalFiles: 1,
                  currentFilePath: request.inputPath,
                  currentFileProgress: reportProgress,
                  currentPosition: currentPosition,
                  totalDuration: duration,
                  message: 'Converting',
                ),
              );
            }

            if (value == 'end') {
              progressState = <String, String>{};
            }
          }
        }
      }
    }

    Future<void> drainStderr() async {
      await for (final line
          in process.stderr
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        final trimmed = line.trim();
        if (trimmed.isNotEmpty) {
          stderrLines.add(trimmed);
        }
      }
    }

    await Future.wait(<Future<void>>[drainStdout(), drainStderr()]);
    final exitCode = await process.exitCode;
    final stdoutText = stdoutLines.isEmpty ? null : stdoutLines.join('\n');
    final stderrText = stderrLines.isEmpty ? null : stderrLines.join('\n');
    final processResult = ProcessResult(
      process.pid,
      exitCode,
      stdoutText ?? '',
      stderrText ?? '',
    );

    final result = _resultFromProcess(
      processResult,
      engine: 'ffmpeg',
      request: request,
      command: _formatCommand(ffmpegPath, args),
    );
    onProgress?.call(
      ConversionProgress(
        completedFiles: 1,
        totalFiles: 1,
        currentFilePath: request.inputPath,
        currentFileProgress: 1,
        currentPosition: duration,
        totalDuration: duration,
        message: result.success ? 'Completed' : 'Failed',
      ),
    );
    return result;
  }

  String? _defaultBundledFfmpegPath() {
    if (!Platform.isWindows && !Platform.isLinux) {
      return null;
    }

    final executableDir = p.dirname(Platform.resolvedExecutable);
    final executableName = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';

    // Prefer a binary placed next to the app executable, then check a few
    // common installer layouts before falling back to PATH.
    final candidates = <String>[
      p.join(executableDir, executableName),
      p.join(executableDir, 'bin', executableName),
      p.join(executableDir, 'lib', executableName),
      p.join(executableDir, 'ffmpeg', executableName),
      p.join(executableDir, 'tools', 'ffmpeg', executableName),
      p.join(executableDir, 'libexec', executableName),
      p.join(executableDir, 'libexec', 'ffmpeg', executableName),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }

  String? _defaultBundledFfprobePath() {
    if (!Platform.isWindows && !Platform.isLinux) {
      return null;
    }

    final executableDir = p.dirname(Platform.resolvedExecutable);
    final executableName = Platform.isWindows ? 'ffprobe.exe' : 'ffprobe';
    final candidates = <String>[
      p.join(executableDir, executableName),
      p.join(executableDir, 'bin', executableName),
      p.join(executableDir, 'lib', executableName),
      p.join(executableDir, 'ffmpeg', executableName),
      p.join(executableDir, 'tools', 'ffmpeg', executableName),
      p.join(executableDir, 'libexec', executableName),
      p.join(executableDir, 'libexec', 'ffmpeg', executableName),
    ];

    for (final candidate in candidates) {
      if (File(candidate).existsSync()) {
        return candidate;
      }
    }

    return null;
  }

  Future<Duration?> _probeDuration(
    String inputPath, {
    String? customFfprobePath,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux)) {
      return null;
    }

    final probePath = customFfprobePath?.trim().isNotEmpty == true
        ? p.join(
            p.dirname(customFfprobePath!.trim()),
            Platform.isWindows ? 'ffprobe.exe' : 'ffprobe',
          )
        : _defaultBundledFfprobePath() ?? 'ffprobe';

    try {
      final result = await Process.run(probePath, <String>[
        '-v',
        'error',
        '-show_entries',
        'format=duration',
        '-of',
        'default=noprint_wrappers=1:nokey=1',
        inputPath,
      ], runInShell: false);
      if (result.exitCode != 0) {
        return null;
      }

      final text = result.stdout?.toString().trim();
      if (text == null || text.isEmpty) {
        return null;
      }

      final seconds = double.tryParse(text);
      if (seconds == null || seconds.isNaN || seconds.isInfinite) {
        return null;
      }

      return Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      return null;
    }
  }

  List<String> _ffmpegArgs(ConvertRequest request) {
    final args = <String>[
      // Audio-only conversions must suppress any video stream, otherwise
      // inputs with embedded cover art can make ffmpeg try to auto-select a
      // video encoder for the output container.
      '-vn',
    ];

    final isOpus = request.outputFormat == AudioFormat.opus;
    final sampleRate = isOpus
        ? _opusSampleRate(request.sampleRate)
        : request.sampleRate;
    if (sampleRate != null) {
      args.addAll(<String>['-ar', sampleRate.toString()]);
    }
    if (request.channels != null) {
      args.addAll(<String>['-ac', request.channels.toString()]);
    }

    final bitRate = request.bitRate;
    final bitRateMode = request.bitRateMode ?? BitRateMode.cbr;
    final bitrateArgs = bitRate == null
        ? const <String>[]
        : switch (bitRateMode) {
            BitRateMode.cbr => <String>['-b:a', bitRate.toString()],
            BitRateMode.vbr => <String>[
              '-q:a',
              _qualityFromBitRate(bitRate).toString(),
            ],
          };

    return switch (request.outputFormat) {
      AudioFormat.aac => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        _aacEncoderName(request),
        '-f',
        'adts',
      ],
      AudioFormat.alac => <String>[...args, '-c:a', 'alac'],
      AudioFormat.aiff => <String>[...args, '-c:a', 'pcm_s16be', '-f', 'aiff'],
      AudioFormat.caf => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        _aacEncoderName(request),
        '-f',
        'caf',
      ],
      AudioFormat.flac => <String>[...args, '-c:a', 'flac'],
      AudioFormat.m4a => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        _aacEncoderName(request),
        '-f',
        'ipod',
      ],
      AudioFormat.m4b => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        _aacEncoderName(request),
        '-f',
        'ipod',
      ],
      AudioFormat.mp3 => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        'libmp3lame',
        '-f',
        'mp3',
      ],
      AudioFormat.ogg => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        'libvorbis',
        '-f',
        'ogg',
      ],
      AudioFormat.opus => <String>[
        ...args,
        if (bitRate != null) ...<String>[
          '-b:a',
          bitRate.toString(),
          '-vbr',
          bitRateMode == BitRateMode.vbr ? 'on' : 'off',
        ],
        '-c:a',
        'libopus',
        '-f',
        'opus',
      ],
      AudioFormat.wav => <String>[...args, '-c:a', 'pcm_s16le', '-f', 'wav'],
    };
  }

  Duration? _durationFromProgressState(Map<String, String> state) {
    final timeUsText = state['out_time_us'];
    if (timeUsText != null) {
      final micros = int.tryParse(timeUsText);
      if (micros != null && micros >= 0) {
        return Duration(microseconds: micros);
      }
    }

    final timeMsText = state['out_time_ms'];
    if (timeMsText != null) {
      final micros = int.tryParse(timeMsText);
      if (micros != null && micros >= 0) {
        return Duration(microseconds: micros);
      }
    }

    final timeText = state['out_time'];
    if (timeText != null) {
      final parsed = _parseDurationText(timeText);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
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

  double? _progressFraction({
    required Duration? currentPosition,
    required Duration? totalDuration,
  }) {
    if (currentPosition == null || totalDuration == null) {
      return null;
    }
    final totalMicros = totalDuration.inMicroseconds;
    if (totalMicros <= 0) {
      return null;
    }

    return (currentPosition.inMicroseconds / totalMicros).clamp(0.0, 1.0);
  }

  Duration? _parseDurationText(String text) {
    final parts = text.split(':');
    if (parts.length != 3) {
      return null;
    }

    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    final seconds = double.tryParse(parts[2]);
    if (hours == null || minutes == null || seconds == null) {
      return null;
    }

    return Duration(
      hours: hours,
      minutes: minutes,
      milliseconds: (seconds * 1000).round(),
    );
  }

  String _aacEncoderName(ConvertRequest request) {
    if (!(Platform.isWindows || Platform.isLinux)) {
      return 'aac';
    }

    return switch (request.aacEncoder ?? AacEncoder.fdkaac) {
      AacEncoder.builtinAac => 'aac',
      AacEncoder.fdkaac => 'libfdk_aac',
    };
  }

  int _qualityFromBitRate(int bitRate) {
    if (bitRate <= 64000) return 9;
    if (bitRate <= 96000) return 6;
    if (bitRate <= 128000) return 5;
    if (bitRate <= 160000) return 4;
    if (bitRate <= 192000) return 3;
    if (bitRate <= 256000) return 2;
    return 1;
  }

  int _opusSampleRate(int? requestedSampleRate) {
    return switch (requestedSampleRate) {
      8000 || 12000 || 16000 || 24000 || 48000 => requestedSampleRate!,
      _ => 48000,
    };
  }

  ConvertResult _resultFromProcess(
    ProcessResult processResult, {
    required String engine,
    required ConvertRequest request,
    required String command,
  }) {
    final stdoutText = processResult.stdout?.toString().trim();
    final stderrText = processResult.stderr?.toString().trim();
    final success = processResult.exitCode == 0;
    return ConvertResult(
      success: success,
      command: command,
      outputPath: success ? request.outputPath : null,
      engine: engine,
      outputFormat: request.outputFormat,
      errorCode: success ? null : 'process_failed',
      errorMessage: success
          ? null
          : _buildFailureMessage(
              engine: engine,
              command: command,
              exitCode: processResult.exitCode,
              stdout: stdoutText,
              stderr: stderrText,
            ),
      stdout: stdoutText?.isEmpty == true ? null : stdoutText,
      stderr: stderrText?.isEmpty == true ? null : stderrText,
      rawLog: _buildRawLog(
        command: command,
        exitCode: processResult.exitCode,
        stdout: stdoutText,
        stderr: stderrText,
      ),
    );
  }

  String _formatCommand(String executable, List<String> args) {
    return <String>[
      executable,
      ...args,
    ].map((part) => part.contains(' ') ? '"$part"' : part).join(' ');
  }

  String _buildFailureMessage({
    required String engine,
    required String command,
    required int exitCode,
    required String? stdout,
    required String? stderr,
  }) {
    final buffer = StringBuffer()
      ..writeln('$engine failed with exit code $exitCode.')
      ..writeln('Command: $command');

    if (stderr != null && stderr.isNotEmpty) {
      buffer.writeln('stderr:');
      buffer.writeln(stderr);
    }

    if (stdout != null && stdout.isNotEmpty) {
      buffer.writeln('stdout:');
      buffer.writeln(stdout);
    }

    return buffer.toString().trimRight();
  }

  String _buildRawLog({
    required String command,
    required int exitCode,
    required String? stdout,
    required String? stderr,
  }) {
    final buffer = StringBuffer()
      ..writeln('command: $command')
      ..writeln('exitCode: $exitCode');

    if (stdout != null && stdout.isNotEmpty) {
      buffer.writeln('stdout:');
      buffer.writeln(stdout);
    }

    if (stderr != null && stderr.isNotEmpty) {
      buffer.writeln('stderr:');
      buffer.writeln(stderr);
    }

    return buffer.toString().trimRight();
  }
}
