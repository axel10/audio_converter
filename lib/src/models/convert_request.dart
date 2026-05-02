import 'audio_format.dart';
import 'bit_rate_mode.dart';

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
    this.allowFallbackToFfmpeg = true,
    this.extraOptions,
  });

  final String inputPath;
  final String outputPath;
  final AudioFormat outputFormat;
  final int? sampleRate;
  final int? channels;
  final int? bitRate;
  final BitRateMode? bitRateMode;
  final String? ffmpegPath;
  final bool allowFallbackToFfmpeg;
  final Map<String, String>? extraOptions;

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
      'allowFallbackToFfmpeg': allowFallbackToFfmpeg,
      'extraOptions': extraOptions,
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
      allowFallbackToFfmpeg: map['allowFallbackToFfmpeg'] as bool? ?? true,
      extraOptions: extraOptions is Map
          ? extraOptions.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : null,
    );
  }
}
