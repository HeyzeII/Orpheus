import 'dart:io';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/debug_logger.dart';

/// Service to handle runtime permission requests on Android.
class PermissionService {
  PermissionService._();

  static const MethodChannel _appControlChannel =
      MethodChannel('com.heyzell.orpheus/app_control');

  static int? _cachedSdkVersion;

  /// Returns the exact Android SDK version (e.g. 33 for Android 13, 30 for Android 11).
  static Future<int> getAndroidSdkVersion() async {
    if (!Platform.isAndroid) return 0;
    if (_cachedSdkVersion != null) return _cachedSdkVersion!;

    try {
      final int? sdk =
          await _appControlChannel.invokeMethod<int>('getAndroidSdkVersion');
      if (sdk != null && sdk > 0) {
        _cachedSdkVersion = sdk;
        return sdk;
      }
    } catch (_) {}

    try {
      final osVersion = Platform.operatingSystemVersion;
      final apiMatch = RegExp(r'API\s+(\d+)').firstMatch(osVersion);
      if (apiMatch != null) {
        _cachedSdkVersion = int.parse(apiMatch.group(1)!);
        return _cachedSdkVersion!;
      }
      final versionMatch = RegExp(r'Android\s+(\d+)').firstMatch(osVersion);
      if (versionMatch != null) {
        final ver = int.parse(versionMatch.group(1)!);
        _cachedSdkVersion = ver >= 13 ? 33 : (ver >= 11 ? 30 : 29);
        return _cachedSdkVersion!;
      }
    } catch (_) {}

    _cachedSdkVersion = 33;
    return _cachedSdkVersion!;
  }

  /// Checks if the app has full filesystem access (MANAGE_EXTERNAL_STORAGE on API 30+).
  /// This is required for `Directory.list()` to see all audio files regardless of MediaStore indexing.
  static Future<bool> hasFullStorageAccess() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();
    if (sdkVersion >= 30) {
      return await Permission.manageExternalStorage.isGranted;
    } else {
      return await Permission.storage.isGranted;
    }
  }

  /// Verifies and explicitly requests full storage access (`MANAGE_EXTERNAL_STORAGE`).
  ///
  /// On Android 11+ (API 30+), if the permission is not granted, this requests it.
  /// If still denied and [openSettingsOnDenied] is true, it redirects the user directly
  /// to the Android system settings screen for "All files access" (Orpheus toggle).
  static Future<bool> checkAndRequestManageExternalStorage({
    bool openSettingsOnDenied = true,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();
    if (sdkVersion < 30) {
      final status = await Permission.storage.request();
      return status.isGranted;
    }

    // Android 11+ (API 30+)
    var isGranted = await Permission.manageExternalStorage.isGranted;
    if (isGranted) return true;

    DebugLogger.log('Solicitando permiso explícito MANAGE_EXTERNAL_STORAGE...');
    final reqStatus = await Permission.manageExternalStorage.request();
    if (reqStatus.isGranted) return true;

    if (openSettingsOnDenied) {
      DebugLogger.log(
          'MANAGE_EXTERNAL_STORAGE denegado. Redirigiendo a pantalla de ajustes...');
      await openManageAllFilesAccess();
      return await Permission.manageExternalStorage.isGranted;
    }

    return false;
  }

  /// Redirects user directly to Android's "All files access" settings screen for Orpheus.
  static Future<void> openManageAllFilesAccess() async {
    if (!Platform.isAndroid) return;

    try {
      final bool? launched = await _appControlChannel
          .invokeMethod<bool>('openManageStorageSettings');
      if (launched == true) return;
    } catch (e) {
      DebugLogger.log('Error invocando openManageStorageSettings nativo: $e');
    }

    // Fallback standard app settings
    await openAppSettings();
  }

  /// Requests storage permissions depending on the Android API level:
  /// - Android 13+ (SDK 33+): Requests [Permission.audio], fallback to [Permission.manageExternalStorage]
  /// - Android 11-12 (SDK 30-32): Requests [Permission.storage] / [Permission.manageExternalStorage]
  /// - Android 10 and below: Requests [Permission.storage]
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      final audioStatus = await Permission.audio.request();
      if (audioStatus.isGranted) return true;
      final manageStatus = await Permission.manageExternalStorage.request();
      return manageStatus.isGranted;
    } else if (sdkVersion >= 30) {
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
      final manageStatus = await Permission.manageExternalStorage.request();
      return manageStatus.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Requests image permissions for cover art updates.
  static Future<bool> requestImagePermission() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// Checks if the app currently has basic storage access permissions.
  static Future<bool> hasStorageAccess() async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();

    if (sdkVersion >= 33) {
      return (await Permission.audio.isGranted) ||
          (await Permission.manageExternalStorage.isGranted);
    } else if (sdkVersion >= 30) {
      return (await Permission.storage.isGranted) ||
          (await Permission.manageExternalStorage.isGranted);
    } else {
      return await Permission.storage.isGranted;
    }
  }

  /// Requests notification permissions for Android 13+ (SDK 33+).
  static Future<bool> requestNotificationPermission({
    VoidCallback? onGranted,
  }) async {
    if (!Platform.isAndroid) return true;

    final sdkVersion = await getAndroidSdkVersion();
    if (sdkVersion < 33) return true;

    final status = await Permission.notification.status;
    if (status.isGranted) return true;

    DebugLogger.log('Lanzando diálogo nativo Permission.notification.request()...');
    final result = await Permission.notification.request();
    DebugLogger.log(
        'Resultado de solicitud POST_NOTIFICATIONS: $result (isGranted: ${result.isGranted})');

    if (result.isGranted && onGranted != null) {
      onGranted();
    }
    return result.isGranted;
  }
}
