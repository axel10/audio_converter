#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint audio_converter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  # Use the pod source root so the path resolves inside the plugin package,
  # not the host app's macos/ directory.
  ffmpeg_lib_arm64 = '$(PODS_ROOT)/../Flutter/ephemeral/.symlinks/plugins/audio_converter/macos/ffmpeg_lib/arm64/lib'
  ffmpeg_lib_x86_64 = '$(PODS_ROOT)/../Flutter/ephemeral/.symlinks/plugins/audio_converter/macos/ffmpeg_lib/amd64/lib'

  s.name             = 'audio_converter'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.module_name      = 'audio_converter'

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '11.0'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'bash "$PODS_TARGET_SRCROOT/../tooling/ensure_ffmpeg_assets.sh" macos $ARCHS && sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust audio_converter',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a"],
  }

  ffmpeg_link_arm64 = [
    "-L#{ffmpeg_lib_arm64}",
    '-lavformat',
    '-lavfilter',
    '-lswscale',
    '-lavcodec',
    '-lmp3lame',
    '-lopus',
    '-lswresample',
    '-lavutil',
  ].join(' ')
  ffmpeg_link_x86_64 = [
    "-L#{ffmpeg_lib_x86_64}",
    '-lavformat',
    '-lavfilter',
    '-lswscale',
    '-lavcodec',
    '-lmp3lame',
    '-lopus',
    '-lswresample',
    '-lavutil',
  ].join(' ')

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[arch=arm64]' => "-force_load ${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a #{ffmpeg_link_arm64}",
    'OTHER_LDFLAGS[arch=x86_64]' => "-force_load ${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a #{ffmpeg_link_x86_64}",
  }
end
