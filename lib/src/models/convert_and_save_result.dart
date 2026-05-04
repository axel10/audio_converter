import 'convert_result.dart';

class ConvertAndSaveResult {
  const ConvertAndSaveResult({
    required this.conversionResult,
    this.savedPath,
    this.temporaryPath,
    this.saveCancelled = false,
    this.saveErrorMessage,
  });

  final ConvertResult conversionResult;
  final String? savedPath;
  final String? temporaryPath;
  final bool saveCancelled;
  final String? saveErrorMessage;

  bool get success =>
      conversionResult.success && !saveCancelled && saveErrorMessage == null;

  String? get outputPath =>
      savedPath ?? temporaryPath ?? conversionResult.outputPath;

  String? get errorMessage {
    if (saveErrorMessage != null) {
      return saveErrorMessage;
    }
    if (saveCancelled) {
      return 'Save dialog was cancelled.';
    }
    return conversionResult.errorMessage;
  }
}
