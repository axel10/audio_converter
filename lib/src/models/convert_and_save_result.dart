import 'convert_result.dart';

class ConvertAndSaveResult {
  const ConvertAndSaveResult({
    required this.conversionResult,
    this.savedPath,
    this.temporaryPath,
    this.saveCancelled = false,
  });

  final ConvertResult conversionResult;
  final String? savedPath;
  final String? temporaryPath;
  final bool saveCancelled;

  bool get success => conversionResult.success && !saveCancelled;

  String? get outputPath =>
      savedPath ?? temporaryPath ?? conversionResult.outputPath;

  String? get errorMessage {
    if (saveCancelled) {
      return 'Save dialog was cancelled.';
    }
    return conversionResult.errorMessage;
  }
}
