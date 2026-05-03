import 'audio_format.dart';
import 'aac_encoder.dart';
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
