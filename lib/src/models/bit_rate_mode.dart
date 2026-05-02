enum BitRateMode {
  cbr,
  vbr,
}

extension BitRateModeX on BitRateMode {
  String get value => switch (this) {
        BitRateMode.cbr => 'cbr',
        BitRateMode.vbr => 'vbr',
      };
}

BitRateMode bitRateModeFromValue(String value) {
  return BitRateMode.values.firstWhere(
    (mode) => mode.value == value,
    orElse: () => throw ArgumentError.value(
      value,
      'value',
      'Unsupported bit rate mode',
    ),
  );
}
