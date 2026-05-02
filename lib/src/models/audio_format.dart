enum AudioFormat {
  aac,
  alac,
  aiff,
  caf,
  flac,
  m4a,
  m4b,
  mp3,
  ogg,
  opus,
  wav,
}

extension AudioFormatX on AudioFormat {
  String get value => switch (this) {
        AudioFormat.aac => 'aac',
        AudioFormat.alac => 'alac',
        AudioFormat.aiff => 'aiff',
        AudioFormat.caf => 'caf',
        AudioFormat.flac => 'flac',
        AudioFormat.m4a => 'm4a',
        AudioFormat.m4b => 'm4b',
        AudioFormat.mp3 => 'mp3',
        AudioFormat.ogg => 'ogg',
        AudioFormat.opus => 'opus',
        AudioFormat.wav => 'wav',
      };
}

AudioFormat audioFormatFromValue(String value) {
  return AudioFormat.values.firstWhere(
    (format) => format.value == value,
    orElse: () => throw ArgumentError.value(value, 'value', 'Unsupported audio format'),
  );
}
