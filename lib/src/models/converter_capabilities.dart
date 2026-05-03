import 'audio_format.dart';
import 'aac_encoder.dart';

class ConverterCapabilities {
  const ConverterCapabilities({
    required this.engine,
    required this.supportedOutputFormats,
    required this.supportsProgress,
    required this.supportsCancellation,
    required this.requiresExternalBinary,
    this.supportedAacEncoders = const <AacEncoder>[],
    this.notes,
  });

  final String engine;
  final List<AudioFormat> supportedOutputFormats;
  final bool supportsProgress;
  final bool supportsCancellation;
  final bool requiresExternalBinary;
  final List<AacEncoder> supportedAacEncoders;
  final String? notes;

  factory ConverterCapabilities.fromMap(Map<Object?, Object?> map) {
    final rawFormats = map['supportedOutputFormats'];
    final formats = rawFormats is List
        ? rawFormats
              .map((value) => audioFormatFromValue(value.toString()))
              .toList(growable: false)
        : const <AudioFormat>[];

    final rawEncoders = map['supportedAacEncoders'];
    final encoders = rawEncoders is List
        ? rawEncoders
              .map((value) => aacEncoderFromValue(value.toString()))
              .toList(growable: false)
        : const <AacEncoder>[];

    return ConverterCapabilities(
      engine: map['engine'] as String? ?? 'unknown',
      supportedOutputFormats: formats,
      supportsProgress: map['supportsProgress'] as bool? ?? false,
      supportsCancellation: map['supportsCancellation'] as bool? ?? false,
      requiresExternalBinary: map['requiresExternalBinary'] as bool? ?? false,
      supportedAacEncoders: encoders,
      notes: map['notes'] as String?,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'engine': engine,
      'supportedOutputFormats': supportedOutputFormats
          .map((format) => format.value)
          .toList(growable: false),
      'supportsProgress': supportsProgress,
      'supportsCancellation': supportsCancellation,
      'requiresExternalBinary': requiresExternalBinary,
      'supportedAacEncoders': supportedAacEncoders
          .map((encoder) => encoder.value)
          .toList(growable: false),
      'notes': notes,
    };
  }
}
