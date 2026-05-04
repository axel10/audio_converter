class AndroidOutputDirectory {
  const AndroidOutputDirectory({
    required this.displayPath,
    required this.treeUri,
  });

  final String displayPath;
  final String treeUri;

  Map<String, Object?> toMap() {
    return <String, Object?>{'displayPath': displayPath, 'treeUri': treeUri};
  }

  factory AndroidOutputDirectory.fromMap(Map<Object?, Object?> map) {
    return AndroidOutputDirectory(
      displayPath: map['displayPath'] as String? ?? '',
      treeUri: map['treeUri'] as String? ?? '',
    );
  }
}
