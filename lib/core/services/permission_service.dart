import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/debug_logger.dart';

/// Service to handle runtime permission requests on Android.
class PermissionService {
  PermissionService._();

  /// Requests storage permissions depending on the Android API level:
  /// - Android 13+ (SDK 33+): Requests [Permission.audio]
  /// - Android 12 and below: Requests [Permission.storage]
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = _getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      final status = await Permission.audio.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Requests image permissions for cover art updates.
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

  /// Requests notification permissions for Android 13+ (SDK 33+).
  static Future<bool> requestNotificationPermission({
    VoidCallback? onGranted,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = _getAndroidSdkVersion();
    if (sdkVersion < 33) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    DebugLogger.log('Lanzando diálogo nativo Permission.notification.request()...');
    final result = await Permission.notification.request();
    DebugLogger.log('Resultado de solicitud POST_NOTIFICATIONS: $result (isGranted: ${result.isGranted})');

    if (result.isGranted && onGranted != null) {
      onGranted();
    }
    return result.isGranted;
  }

  static int _getAndroidSdkVersion() {
    try {
      final osVersion = Platform.operatingSystemVersion;
      final apiMatch = RegExp(r'API\s+(\d+)').firstMatch(osVersion);
      if (apiMatch != null) {
        return int.parse(apiMatch.group(1)!);
      }
      final versionMatch = RegExp(r'Android\s+(\d+)').firstMatch(osVersion);
      if (versionMatch != null) {
        final ver = int.parse(versionMatch.group(1)!);
        return ver >= 13 ? 33 : 30;
      }
    } catch (_) {}
    return 33;
  }
}
