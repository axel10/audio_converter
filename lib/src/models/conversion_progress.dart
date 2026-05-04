class ConversionProgress {
  const ConversionProgress({
    required this.completedFiles,
    required this.totalFiles,
    required this.currentFilePath,
    this.currentFileProgress,
    this.currentPosition,
    this.totalDuration,
    this.message,
  });

  final int completedFiles;
  final int totalFiles;
  final String currentFilePath;
  final double? currentFileProgress;
  final Duration? currentPosition;
  final Duration? totalDuration;
  final String? message;

  int get currentFileIndex {
    if (totalFiles <= 0) {
      return 0;
    }

    return completedFiles >= totalFiles ? totalFiles : completedFiles + 1;
  }

  double? get overallProgress {
    if (totalFiles <= 0) {
      return null;
    }

    final current = currentFileProgress;
    final completedFraction = completedFiles / totalFiles;
    if (current == null) {
      return completedFraction;
    }

    return ((completedFiles + current.clamp(0.0, 1.0)) / totalFiles)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  ConversionProgress copyWith({
    int? completedFiles,
    int? totalFiles,
    String? currentFilePath,
    double? currentFileProgress,
    Duration? currentPosition,
    Duration? totalDuration,
    String? message,
  }) {
    return ConversionProgress(
      completedFiles: completedFiles ?? this.completedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      currentFilePath: currentFilePath ?? this.currentFilePath,
      currentFileProgress: currentFileProgress ?? this.currentFileProgress,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      message: message ?? this.message,
    );
  }
}

typedef AudioConverterProgressCallback =
    void Function(ConversionProgress progress);
