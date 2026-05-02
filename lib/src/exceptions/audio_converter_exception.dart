class AudioConverterException implements Exception {
  const AudioConverterException(
    this.code,
    this.message, {
    this.details,
  });

  final String code;
  final String message;
  final Object? details;

  @override
  String toString() => 'AudioConverterException($code): $message';
}
