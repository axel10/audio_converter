/// This is copied from Cargokit (which is the official way to use it currently)
/// Details: https://fzyzcjy.github.io/flutter_rust_bridge/manual/integrate/builtin

import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as path;

import 'artifacts_provider.dart';
import 'builder.dart';
import 'environment.dart';
import 'options.dart';
import 'target.dart';
import 'util.dart';

final _log = Logger('build_pod');

class BuildPod {
  BuildPod({required this.userOptions});

  final CargokitUserOptions userOptions;

  Future<void> build() async {
    final targets = Environment.darwinArchs.map((arch) {
      final target = Target.forDarwin(
          platformName: Environment.darwinPlatformName, darwinAarch: arch);
      if (target == null) {
        throw Exception(
            "Unknown darwin target or platform: $arch, ${Environment.darwinPlatformName}");
      }
      return target;
    }).where((target) {
      if (target.darwinPlatform == null || target.darwinArch == null) {
        return true;
      }

      if (target.darwinPlatform == 'macosx') {
        return true;
      }

      final manifestRoot = path.dirname(Environment.manifestDir);
      final ffmpegDir = switch ((target.darwinPlatform, target.darwinArch)) {
        ('iphoneos', 'arm64') =>
          path.join(manifestRoot, 'ios', 'ffmpeg_lib', 'arm64'),
        ('iphonesimulator', 'arm64') =>
          path.join(manifestRoot, 'ios', 'ffmpeg_lib', 'arm64-sim'),
        ('iphonesimulator', 'x86_64') =>
          path.join(manifestRoot, 'ios', 'ffmpeg_lib', 'x86_64'),
        _ => '',
      };
      if (ffmpegDir.isEmpty) {
        return false;
      }

      final exists = Directory(ffmpegDir).existsSync();
      if (!exists) {
        _log.warning(
            'Skipping unsupported darwin target $target because $ffmpegDir does not exist');
      }
      return exists;
    }).toList();

    final environment = BuildEnvironment.fromEnvironment(isAndroid: false);
    final provider =
        ArtifactProvider(environment: environment, userOptions: userOptions);
    final artifacts = await provider.getArtifacts(targets);

    void performLipo(String targetFile, Iterable<String> sourceFiles) {
      runCommand("lipo", [
        '-create',
        ...sourceFiles,
        '-output',
        targetFile,
      ]);
    }

    final outputDir = Environment.outputDir;

    Directory(outputDir).createSync(recursive: true);

    final staticLibs = artifacts.values
        .expand((element) => element)
        .where((element) => element.type == AritifactType.staticlib)
        .toList();
    final dynamicLibs = artifacts.values
        .expand((element) => element)
        .where((element) => element.type == AritifactType.dylib)
        .toList();

    final libName = environment.crateInfo.packageName;

    // If there is static lib, use it and link it with pod
    if (staticLibs.isNotEmpty) {
      final finalTargetFile = path.join(outputDir, "lib$libName.a");
      performLipo(finalTargetFile, staticLibs.map((e) => e.path));
    } else {
      // Otherwise try to replace bundle dylib with our dylib
      final bundlePaths = [
        '$libName.framework/Versions/A/$libName',
        '$libName.framework/$libName',
      ];

      for (final bundlePath in bundlePaths) {
        final targetFile = path.join(outputDir, bundlePath);
        if (File(targetFile).existsSync()) {
          performLipo(targetFile, dynamicLibs.map((e) => e.path));

          // Replace absolute id with @rpath one so that it works properly
          // when moved to Frameworks.
          runCommand("install_name_tool", [
            '-id',
            '@rpath/$bundlePath',
            targetFile,
          ]);
          return;
        }
      }
      throw Exception('Unable to find bundle for dynamic library');
    }
  }
}
