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

  static bool _isRequestingNotificationPermission = false;

  /// Requests notification permissions for Android 13+ (SDK 33+).
  /// Returns `true` if the permission is granted (either already was or just granted now),
  /// `false` if denied or not on Android 13+.
  /// The [onGranted] callback is invoked only if permission was **newly** approved
  /// during this call (i.e., was not granted before the dialog appeared).
  static Future<bool> requestNotificationPermission({
    VoidCallback? onGranted,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = _getAndroidSdkVersion();
    if (sdkVersion < 33) {
      DebugLogger.log('Notification permission check: Android SDK $sdkVersion (< 33) does not require POST_NOTIFICATIONS');
      return true;
    }

    final before = await Permission.notification.status;
    DebugLogger.log('Estado previo de permiso POST_NOTIFICATIONS: $before');
    if (before.isGranted) return true;

    if (_isRequestingNotificationPermission) {
      DebugLogger.log('Solicitud POST_NOTIFICATIONS ya en curso, omitiendo duplicada.');
      return before.isGranted;
    }

    _isRequestingNotificationPermission = true;
    try {
      DebugLogger.log('Lanzando dialogo nativo Permission.notification.request()...');
      final status = await Permission.notification.request();
      final isGranted = status.isGranted;
      DebugLogger.log('Resultado de solicitud POST_NOTIFICATIONS: $status (isGranted: $isGranted)');

      if (isGranted) {
        if (!before.isGranted && onGranted != null) {
          onGranted();
        }
      } else {
        DebugLogger.log('⚠️ ALERTA: Permiso de notificaciones POST_NOTIFICATIONS fue denegado por el usuario o SO ($status).');
      }
      return isGranted;
    } catch (e, s) {
      DebugLogger.log('ERROR al solicitar POST_NOTIFICATIONS: $e\n$s');
      return false;
    } finally {
      _isRequestingNotificationPermission = false;
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
