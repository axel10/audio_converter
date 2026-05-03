enum AacEncoder { builtinAac, fdkaac }

extension AacEncoderX on AacEncoder {
  String get value => switch (this) {
    AacEncoder.builtinAac => 'builtinAac',
    AacEncoder.fdkaac => 'fdkaac',
  };

  String get label => switch (this) {
    AacEncoder.builtinAac => 'Built-in AAC',
    AacEncoder.fdkaac => 'FDK-AAC',
  };
}

AacEncoder aacEncoderFromValue(String value) {
  return AacEncoder.values.firstWhere(
    (encoder) => encoder.value == value,
    orElse: () =>
        throw ArgumentError.value(value, 'value', 'Unsupported AAC encoder'),
  );
}
