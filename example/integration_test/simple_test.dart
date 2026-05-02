import 'dart:io';

import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audio_converter/audio_converter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  test('Can call rust function', () async {
    if (Platform.isMacOS) {
      return;
    }

    await RustLib.init(forceSameCodegenVersion: false);
    expect(greet(name: "Tom"), "Hello, Tom!");
  });
}
