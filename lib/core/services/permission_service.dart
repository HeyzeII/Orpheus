import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// Service to handle runtime permission requests on Android.
class PermissionService {
  PermissionService._();

  /// Requests storage permissions depending on the Android API level:
  /// - Android 13+ (SDK 33+): Requests [Permission.audio]
  /// - Android 12 and below: Requests [Permission.storage]
  /// Returns `true` if granted, `false` otherwise.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Check SDK version via Platform.version or similar, but permission_handler handles this internally
    // if we request Permission.audio on older versions, it might fail or return permanentlyDenied.
    // In Android SDK 33+, Permission.storage returns isDenied/permanentlyDenied always.
    // To check the API level precisely in pure Dart, we can parse Platform.operatingSystemVersion or use permission_handler's own logic.
    // Actually, permission_handler requests the correct platform manifest declaration.
    // Let's parse OS version to check SDK level:
    final sdkVersion = _getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      final status = await Permission.audio.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Requests image permissions for cover art updates depending on the Android API level:
  /// - Android 13+ (SDK 33+): Requests [Permission.photos]
  /// - Android 12 and below: Requests [Permission.storage]
  /// Returns `true` if granted, `false` otherwise.
  static Future<bool> requestImagePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = _getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Checks if the app currently has storage access permissions.
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = _getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      return await Permission.audio.isGranted;
    } else {
      return await Permission.storage.isGranted;
    }
  }

  /// Parses Android SDK version from Platform.operatingSystemVersion.
  /// Typically looks like: "Android 14 (API 34)" or "13"
  static int _getAndroidSdkVersion() {
    try {
      final osVersion = Platform.operatingSystemVersion;
      final apiMatch = RegExp(r'API\s+(\d+)').firstMatch(osVersion);
      if (apiMatch != null) {
        return int.parse(apiMatch.group(1)!);
      }
      // Fallback parsing from Android version number
      final versionMatch = RegExp(r'Android\s+(\d+)').firstMatch(osVersion);
      if (versionMatch != null) {
        final ver = int.parse(versionMatch.group(1)!);
        return ver >= 13 ? 33 : 30; // rough estimation
      }
    } catch (_) {}
    return 33; // Default to modern SDK behavior
  }
}
