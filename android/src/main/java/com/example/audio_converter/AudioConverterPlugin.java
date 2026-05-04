package com.example.audio_converter;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.util.Log;
import android.webkit.MimeTypeMap;

import androidx.annotation.NonNull;
import androidx.documentfile.provider.DocumentFile;

import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry.ActivityResultListener;

public class AudioConverterPlugin
    implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware, ActivityResultListener {
  private static final String TAG = "AudioConverterPlugin";
  private static final String CHANNEL = "com.example.audio_converter/saf";
  private static final int REQUEST_PICK_OUTPUT_DIRECTORY = 42_109;

  private FlutterPluginBinding pluginBinding;
  private ActivityPluginBinding activityBinding;
  private Activity activity;
  private MethodChannel channel;
  private MethodChannel.Result pendingDirectoryResult;

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    pluginBinding = binding;
    maybeCreateChannel();
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
    tearDownChannel();
    pluginBinding = null;
  }

  @Override
  public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
    activityBinding = binding;
    activity = binding.getActivity();
    binding.addActivityResultListener(this);
    maybeCreateChannel();
  }

  @Override
  public void onDetachedFromActivityForConfigChanges() {
    tearDownActivity();
  }

  @Override
  public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
    onAttachedToActivity(binding);
  }

  @Override
  public void onDetachedFromActivity() {
    tearDownActivity();
  }

  @Override
  public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
    switch (call.method) {
      case "pickOutputDirectory":
        pickOutputDirectory(result);
        break;
      case "saveFileToDirectory":
        saveFileToDirectory(call.arguments, result);
        break;
      default:
        result.notImplemented();
    }
  }

  @Override
  public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
    if (requestCode != REQUEST_PICK_OUTPUT_DIRECTORY) {
      return false;
    }

    final MethodChannel.Result result = pendingDirectoryResult;
    pendingDirectoryResult = null;

    if (result == null) {
      return true;
    }

    if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
      result.success(null);
      return true;
    }

    final Uri treeUri = data.getData();
    final int takeFlags = data.getFlags()
        & (Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
    try {
      activity.getContentResolver().takePersistableUriPermission(treeUri, takeFlags);
    } catch (SecurityException error) {
      Log.w(TAG, "Failed to persist SAF permission for " + treeUri, error);
    }

    final Map<String, Object> response = new HashMap<>();
    response.put("treeUri", treeUri.toString());
    response.put("displayPath", resolveDisplayPath(treeUri));
    result.success(response);
    return true;
  }

  private void pickOutputDirectory(MethodChannel.Result result) {
    if (activity == null) {
      result.error("no_activity", "Android activity is not available.", null);
      return;
    }
    if (pendingDirectoryResult != null) {
      result.error("already_active", "A directory picker is already active.", null);
      return;
    }

    pendingDirectoryResult = result;
    final Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
    intent.addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION);
    intent.addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      intent.putExtra(
          DocumentsContract.EXTRA_INITIAL_URI,
          Uri.parse("content://com.android.externalstorage.documents/root/primary")
      );
    }

    try {
      activity.startActivityForResult(intent, REQUEST_PICK_OUTPUT_DIRECTORY);
    } catch (Exception error) {
      pendingDirectoryResult = null;
      result.error("directory_picker_failed", error.getMessage(), null);
    }
  }

  private void saveFileToDirectory(Object arguments, MethodChannel.Result result) {
    if (activity == null) {
      result.error("no_activity", "Android activity is not available.", null);
      return;
    }
    if (!(arguments instanceof Map)) {
      result.error("invalid_arguments", "Expected a map of arguments.", null);
      return;
    }

    final Map<?, ?> args = (Map<?, ?>) arguments;
    final String treeUriString = stringArg(args, "treeUri");
    final String sourcePath = stringArg(args, "sourcePath");
    final String fileName = stringArg(args, "fileName");
    if (treeUriString == null || treeUriString.isEmpty()) {
      result.error("invalid_arguments", "Missing treeUri.", null);
      return;
    }
    if (sourcePath == null || sourcePath.isEmpty()) {
      result.error("invalid_arguments", "Missing sourcePath.", null);
      return;
    }
    if (fileName == null || fileName.isEmpty()) {
      result.error("invalid_arguments", "Missing fileName.", null);
      return;
    }

    final Uri treeUri = Uri.parse(treeUriString);
    final DocumentFile tree = DocumentFile.fromTreeUri(activity, treeUri);
    if (tree == null) {
      result.error("save_failed", "Failed to resolve the selected directory.", null);
      return;
    }

    try {
      final DocumentFile existing = tree.findFile(fileName);
      if (existing != null) {
        existing.delete();
      }

      final DocumentFile created = tree.createFile(mimeTypeForFileName(fileName), fileName);
      if (created == null) {
        result.error("save_failed", "Failed to create the output file.", null);
        return;
      }

      try (InputStream input = new FileInputStream(sourcePath);
           OutputStream output = activity.getContentResolver().openOutputStream(created.getUri(), "w")) {
        if (output == null) {
          result.error("save_failed", "Failed to open the output stream.", null);
          return;
        }

        final byte[] buffer = new byte[8192];
        int read;
        while ((read = input.read(buffer)) != -1) {
          output.write(buffer, 0, read);
        }
        output.flush();
      }

      final Map<String, Object> response = new HashMap<>();
      response.put("savedUri", created.getUri().toString());
      response.put("displayPath", resolveDisplayPath(treeUri) + "/" + fileName);
      result.success(response);
    } catch (IOException error) {
      Log.e(TAG, "Failed to copy output file into SAF directory", error);
      result.error("save_failed", error.getMessage(), null);
    }
  }

  private void maybeCreateChannel() {
    if (channel != null || pluginBinding == null || activity == null) {
      return;
    }

    channel = new MethodChannel(pluginBinding.getBinaryMessenger(), CHANNEL);
    channel.setMethodCallHandler(this);
  }

  private void tearDownActivity() {
    if (activityBinding != null) {
      activityBinding.removeActivityResultListener(this);
    }
    activityBinding = null;
    activity = null;
    pendingDirectoryResult = null;
  }

  private void tearDownChannel() {
    if (channel != null) {
      channel.setMethodCallHandler(null);
    }
    channel = null;
  }

  private static String stringArg(Map<?, ?> args, String key) {
    final Object value = args.get(key);
    return value == null ? null : value.toString();
  }

  private static String resolveDisplayPath(Uri treeUri) {
    final String docId = DocumentsContract.getTreeDocumentId(treeUri);
    final String[] parts = docId.split(":");
    if (parts.length > 1) {
      if ("primary".equalsIgnoreCase(parts[0])) {
        return Environment.getExternalStorageDirectory() + "/" + parts[1];
      }
      return "/storage/" + parts[0] + "/" + parts[1];
    }

    return treeUri.toString();
  }

  private static String mimeTypeForFileName(String fileName) {
    final int dotIndex = fileName.lastIndexOf('.');
    if (dotIndex < 0 || dotIndex == fileName.length() - 1) {
      return "application/octet-stream";
    }

    final String extension = fileName.substring(dotIndex + 1).toLowerCase(Locale.US);
    final String mimeType = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
    return mimeType == null ? "application/octet-stream" : mimeType;
  }
}
