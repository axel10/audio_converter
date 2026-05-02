#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint audio_converter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  ffmpeg_lib_ios = '$(PROJECT_DIR)/../../ios/ffmpeg_lib/arm64/lib'
  ffmpeg_lib_sim = '$(PROJECT_DIR)/../../ios/ffmpeg_lib/arm64-sim/lib'

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
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.frameworks = 'AVFoundation', 'AudioToolbox'
  s.platform = :ios, '11.0'

  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # First argument is relative path to the `rust` folder, second is name of rust library
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust audio_converter',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    # Let XCode know that the static library referenced in -force_load below is
    # created by this build step.
    :output_files => ["${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a"],
  }
  ffmpeg_link_ios = [
    "-L#{ffmpeg_lib_ios}",
    '-lavformat',
    '-lavfilter',
    '-lswscale',
    '-lavcodec',
    '-lmp3lame',
    '-lopus',
    '-lswresample',
    '-lavutil',
  ].join(' ')
  ffmpeg_link_sim = [
    "-L#{ffmpeg_lib_sim}",
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
    # Flutter.framework does not contain a i386 slice, and we only ship arm64
    # simulator FFmpeg binaries in this repo.
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS[sdk=iphoneos*]' => "-force_load ${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a #{ffmpeg_link_ios}",
    'OTHER_LDFLAGS[sdk=iphonesimulator*]' => "-force_load ${PODS_CONFIGURATION_BUILD_DIR}/audio_converter/libaudio_converter.a #{ffmpeg_link_sim}",
  }
end
