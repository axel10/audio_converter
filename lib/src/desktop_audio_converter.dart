import 'dart:convert';
import 'dart:io';

import 'models/audio_format.dart';
import 'models/bit_rate_mode.dart';
import 'models/convert_request.dart';
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

  bool _usesAfconvertForMacOS(ConvertRequest request) {
    return Platform.isMacOS &&
        (request.outputFormat == AudioFormat.aac ||
            request.outputFormat == AudioFormat.m4a);
  }

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

  Future<ConvertResult> convertFile(ConvertRequest request) async {
    if (_usesAfconvertForMacOS(request)) {
      return _convertWithAfconvert(request);
    }
    if (_usesBundledRustFfmpeg) {
      await _ensureRustInitialized();
      return _convertWithRustFfmpeg(request);
    }
    if (Platform.isWindows || Platform.isLinux) {
      return _convertWithFfmpeg(request);
    }
    return const ConvertResult(
      success: false,
      errorCode: 'unsupported_platform',
      errorMessage:
          'Audio converter is only available on Android, iOS, macOS, Windows, and Linux.',
    );
  }

  Future<ConverterCapabilities> getCapabilities() async {
    if (_usesBundledRustFfmpeg) {
      await _ensureRustInitialized();
      final raw = await rust_api.androidGetCapabilities();
      final capabilities = ConverterCapabilities.fromMap(
        jsonDecode(raw) as Map<Object?, Object?>,
      );
      if (Platform.isMacOS) {
        return ConverterCapabilities(
          engine: capabilities.engine,
          supportedOutputFormats: capabilities.supportedOutputFormats,
          supportsProgress: capabilities.supportsProgress,
          supportsCancellation: capabilities.supportsCancellation,
          requiresExternalBinary: capabilities.requiresExternalBinary,
          notes: [
            capabilities.notes,
            'On macOS, AAC and M4A conversions still use afconvert.',
          ].whereType<String>().join(' '),
        );
      }
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
        supportsProgress: false,
        supportsCancellation: false,
        requiresExternalBinary: true,
        notes: 'Uses a user-provided ffmpeg binary or one available on PATH.',
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

  Future<ConvertResult> _convertWithRustFfmpeg(ConvertRequest request) async {
    final raw = await rust_api.androidConvertFile(
      requestJson: jsonEncode(request.toMap()),
    );
    return ConvertResult.fromMap(jsonDecode(raw) as Map<Object?, Object?>);
  }

  Future<ConvertResult> _convertWithAfconvert(ConvertRequest request) async {
    final args = <String>[
      request.inputPath,
      request.outputPath,
      ..._afconvertArgs(request),
    ];

    final processResult = await Process.run(
      'afconvert',
      args,
      runInShell: false,
    );

    return _resultFromProcess(
      processResult,
      engine: 'afconvert',
      request: request,
      command: _formatCommand('afconvert', args),
    );
  }

  List<String> _afconvertArgs(ConvertRequest request) {
    final strategy = request.bitRateMode == BitRateMode.vbr ? '3' : '0';
    final bitRateArgs = request.bitRate == null
        ? const <String>[]
        : <String>['-b', request.bitRate!.toString()];

    return switch (request.outputFormat) {
      AudioFormat.aac => <String>[
        '-f',
        'adts',
        '-d',
        'aac ',
        '-s',
        strategy,
        ...bitRateArgs,
      ],
      AudioFormat.alac => const <String>['-f', 'm4af', '-d', 'alac'],
      AudioFormat.aiff => const <String>['-f', 'AIFF', '-d', 'BEI16'],
      AudioFormat.caf => <String>[
        '-f',
        'caff',
        '-d',
        'aac ',
        '-s',
        strategy,
        ...bitRateArgs,
      ],
      AudioFormat.flac => const <String>['-f', 'flac', '-d', 'flac'],
      AudioFormat.m4a => <String>[
        '-f',
        'm4af',
        '-d',
        'aac ',
        '-s',
        strategy,
        ...bitRateArgs,
      ],
      AudioFormat.m4b => <String>[
        '-f',
        'm4bf',
        '-d',
        'aac ',
        '-s',
        strategy,
        ...bitRateArgs,
      ],
      AudioFormat.mp3 => const <String>['-f', 'MPG3', '-d', '.mp3'],
      AudioFormat.ogg => const <String>['-f', 'Oggf', '-d', 'vorb'],
      AudioFormat.opus => const <String>['-f', 'Oggf', '-d', 'opus'],
      AudioFormat.wav => const <String>['-f', 'WAVE', '-d', 'LEI16'],
    };
  }

  Future<ConvertResult> _convertWithFfmpeg(ConvertRequest request) async {
    final ffmpegPath = request.ffmpegPath?.trim().isNotEmpty == true
        ? request.ffmpegPath!.trim()
        : 'ffmpeg';
    final args = <String>[
      '-y',
      '-i',
      request.inputPath,
      ..._ffmpegArgs(request),
      request.outputPath,
    ];

    final processResult = await Process.run(
      ffmpegPath,
      args,
      runInShell: false,
    );

    return _resultFromProcess(
      processResult,
      engine: 'ffmpeg',
      request: request,
      command: _formatCommand(ffmpegPath, args),
    );
  }

  List<String> _ffmpegArgs(ConvertRequest request) {
    final args = <String>[];

    if (request.sampleRate != null) {
      args.addAll(<String>['-ar', request.sampleRate.toString()]);
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
        'aac',
        '-f',
        'adts',
      ],
      AudioFormat.alac => <String>[...args, '-c:a', 'alac'],
      AudioFormat.aiff => <String>[...args, '-c:a', 'pcm_s16be', '-f', 'aiff'],
      AudioFormat.caf => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        'aac',
        '-f',
        'caf',
      ],
      AudioFormat.flac => <String>[...args, '-c:a', 'flac'],
      AudioFormat.m4a => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        'aac',
        '-f',
        'ipod',
      ],
      AudioFormat.m4b => <String>[
        ...args,
        ...bitrateArgs,
        '-c:a',
        'aac',
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
        ...bitrateArgs,
        '-c:a',
        'libopus',
        '-f',
        'opus',
      ],
      AudioFormat.wav => <String>[...args, '-c:a', 'pcm_s16le', '-f', 'wav'],
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
