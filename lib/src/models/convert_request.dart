import 'dart:io';

import 'audio_format.dart';
import 'aac_encoder.dart';
import 'bit_rate_mode.dart';
import 'package:path/path.dart' as p;

class ConvertRequest {
  const ConvertRequest({
    required this.inputPath,
    required this.outputPath,
    required this.outputFormat,
    this.sampleRate,
    this.channels,
    this.bitRate,
    this.bitRateMode,
    this.ffmpegPath,
    this.aacEncoder,
    this.allowFallbackToFfmpeg = true,
    this.extraOptions,
    this.customArgs,
  });

  final String inputPath;
  final String outputPath;
  final AudioFormat outputFormat;
  final int? sampleRate;
  final int? channels;
  final int? bitRate;
  final BitRateMode? bitRateMode;
  final String? ffmpegPath;
  final AacEncoder? aacEncoder;
  final bool allowFallbackToFfmpeg;
  final Map<String, String>? extraOptions;
  final List<String>? customArgs;

  ConvertRequest copyWith({
    String? inputPath,
    String? outputPath,
    AudioFormat? outputFormat,
    int? sampleRate,
    int? channels,
    int? bitRate,
    BitRateMode? bitRateMode,
    String? ffmpegPath,
    AacEncoder? aacEncoder,
    bool? allowFallbackToFfmpeg,
    Map<String, String>? extraOptions,
    List<String>? customArgs,
  }) {
    return ConvertRequest(
      inputPath: inputPath ?? this.inputPath,
      outputPath: outputPath ?? this.outputPath,
      outputFormat: outputFormat ?? this.outputFormat,
      sampleRate: sampleRate ?? this.sampleRate,
      channels: channels ?? this.channels,
      bitRate: bitRate ?? this.bitRate,
      bitRateMode: bitRateMode ?? this.bitRateMode,
      ffmpegPath: ffmpegPath ?? this.ffmpegPath,
      aacEncoder: aacEncoder ?? this.aacEncoder,
      allowFallbackToFfmpeg:
          allowFallbackToFfmpeg ?? this.allowFallbackToFfmpeg,
      extraOptions: extraOptions ?? this.extraOptions,
      customArgs: customArgs ?? this.customArgs,
    );
  }

  factory ConvertRequest.forMobile({
    required String inputPath,
    required AudioFormat outputFormat,
    int? sampleRate,
    int? channels,
    int? bitRate,
    BitRateMode? bitRateMode,
    String? ffmpegPath,
    AacEncoder? aacEncoder,
    bool allowFallbackToFfmpeg = true,
    Map<String, String>? extraOptions,
    List<String>? customArgs,
  }) {
    final baseName = p.basenameWithoutExtension(inputPath);
    final tempDir = Directory(
      p.join(Directory.systemTemp.path, 'audio_converter'),
    );

    return ConvertRequest(
      inputPath: inputPath,
      outputPath: p.join(tempDir.path, '$baseName.${outputFormat.value}'),
      outputFormat: outputFormat,
      sampleRate: sampleRate,
      channels: channels,
      bitRate: bitRate,
      bitRateMode: bitRateMode,
      ffmpegPath: ffmpegPath,
      aacEncoder: aacEncoder,
      allowFallbackToFfmpeg: allowFallbackToFfmpeg,
      extraOptions: extraOptions,
      customArgs: customArgs,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'inputPath': inputPath,
      'outputPath': outputPath,
      'outputFormat': outputFormat.value,
      'sampleRate': sampleRate,
      'channels': channels,
      'bitRate': bitRate,
      'bitRateMode': bitRateMode?.value,
      'ffmpegPath': ffmpegPath,
      'aacEncoder': aacEncoder?.value,
      'allowFallbackToFfmpeg': allowFallbackToFfmpeg,
      'extraOptions': extraOptions,
      'customArgs': customArgs,
    };
  }

  factory ConvertRequest.fromMap(Map<Object?, Object?> map) {
    final extraOptions = map['extraOptions'];
    return ConvertRequest(
      inputPath: map['inputPath'] as String,
      outputPath: map['outputPath'] as String,
      outputFormat: audioFormatFromValue(map['outputFormat'] as String),
      sampleRate: map['sampleRate'] as int?,
      channels: map['channels'] as int?,
      bitRate: map['bitRate'] as int?,
      bitRateMode: map['bitRateMode'] == null
          ? null
          : bitRateModeFromValue(map['bitRateMode'] as String),
      ffmpegPath: map['ffmpegPath'] as String?,
      aacEncoder: map['aacEncoder'] == null
          ? null
          : aacEncoderFromValue(map['aacEncoder'] as String),
      allowFallbackToFfmpeg: map['allowFallbackToFfmpeg'] as bool? ?? true,
      extraOptions: extraOptions is Map
          ? extraOptions.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : null,
      customArgs: map['customArgs'] is List
          ? (map['customArgs'] as List)
                .map((value) => value.toString())
                .toList(growable: false)
          : null,
    );
  }
}
